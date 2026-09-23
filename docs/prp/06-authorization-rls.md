# 06 — Authorization & Row Level Security (RLS)

> **Authorization** = deciding what a logged-in person may see and do.
> **RLS (Row Level Security)** = rules inside PostgreSQL that are checked for **every row** of every query. If a rule says "no", the row is invisible or the change is refused, no matter where the request came from.
> **Policy** = one RLS rule, e.g. "members of an organization may read its customers".

---

## 1. Three levels of security

| Level | Where | What it does | Can it be bypassed? |
|---|---|---|---|
| 1. UI | Browser (menus, buttons) | Hides pages and buttons the role cannot use. Only for a clean experience. | **Yes** — anyone can type a URL or call the API. Never relied on. |
| 2. Server | Next.js layouts, pages, Server Actions (`requireMembership`, `requirePlatformAdmin`, Zod) | Checks login, account, membership, organization status, role and input **before** every read and every action. Gives friendly errors. | Only by a bug in our code. |
| 3. Database | RLS policies, helper functions, triggers, constraints, column grants | The final wall. Even with a bug in levels 1–2, or a direct call to Supabase with the public key, data of another organization or another client cannot be read or changed. | No (only the secret key bypasses it, and that key never leaves the server — `03-architecture.md` §4.1). |

Rule: **every permission in `02-roles-permissions.md` exists at level 2 AND level 3.**

## 2. Basic setup for every table

1. `alter table … enable row level security;` in the same migration that creates the table.
2. Policies are written **for the `authenticated` role only** (logged-in users). The `anon` role (not logged in, but holding the public key) gets **no** policies and no grants on business tables → it sees nothing.
3. Separate policies for `select`, `insert`, `update`, `delete` (never one "all" policy — easier to read and test).
4. Every `update` policy has both `using` (which rows may be changed) **and** `with check` (what the row must look like afterwards), so a row cannot be "moved" into something the user may not own.
5. **Column grants** limit which columns a normal user may update at all (e.g. `grant update (name, timezone) on organizations to authenticated`). Columns like `status`, `organization_id`, `created_by`, totals, `invoice_number` are **not** granted, so they can only change through triggers or trusted database functions.
6. Actions that change several rows or need extra checks (creating an organization, accepting invitations, changing roles, issuing invoices, payments) are done **only** through **database functions** (called "RPC" — remote procedure call — from the server). The table itself then has **no** insert/update/delete policy for that action, so the function is the only door.

## 3. Helper functions

Policies call small SQL functions so that the rules are written once and used everywhere.

### 3.1 Words used

- **`security definer`**: the function runs with the rights of the function's owner (not of the user calling it). This lets it read `memberships` even though the user's own RLS would limit that. It must therefore be written very carefully and only return true/false or an ID.
- **Fixed `search_path`**: `set search_path = ''` — the function does not look up tables by "nearest name"; every table is written with its schema (`public.memberships`). This stops an attacker from creating a fake table with the same name that the function would use by mistake.
- **`stable`**: tells PostgreSQL the answer does not change within one query, so it can reuse it.
- **`(select auth.uid())`**: `auth.uid()` returns the logged-in user's ID from their verified token. Wrapping it in `select` makes PostgreSQL compute it once per query instead of once per row (much faster on big tables).
- **`private` schema**: helper functions live in a schema (a folder inside the database) called `private`, which Supabase's automatic API does **not** expose, so nobody can call them directly from the browser. Only the RPC functions that the app needs live in `public`.

### 3.2 The functions

| Function | Returns | Meaning |
|---|---|---|
| `private.is_platform_admin()` | boolean | Current user is in `platform_admins` and their profile is active |
| `private.is_member(org uuid)` | boolean | Current user has an **active** membership in `org`, the organization is `active`, and their profile is `active` |
| `private.my_role(org uuid)` | text | The current user's role in `org` (null if not an active member) |
| `private.has_role(org uuid, roles text[])` | boolean | `is_member(org)` and `my_role(org) = any(roles)` |
| `private.my_membership_id(org uuid)` | uuid | Current user's membership ID in `org` |
| `private.client_customer_id(org uuid)` | uuid | For a CLIENT: the linked `customer_id`; for others: null |
| `private.is_project_member(org uuid, project uuid)` | boolean | Current user's membership is in `project_members` for that project |
| `private.org_writable(org uuid)` | boolean | The organization may be changed: subscription allows writing (D-25). Before Step 22 it simply returns true |
| `private.can_write(org uuid, roles text[])` | boolean | `has_role(org, roles)` **and** `org_writable(org)` — used in every insert/update/delete policy |
| `private.clients_see_tasks(org uuid)` | boolean | Value of `organization_settings.clients_can_see_tasks` |
| `private.org_limits(org uuid)` | record | Plan limits + current usage (`12-billing-subscriptions.md` §5) |
| `private.notify(...)` | — | Inserts notifications, skipping the acting user (`11-notifications-audit.md` §1.3) |
| `private.audit_row_change()` | trigger | Writes `activity_logs` (`11-notifications-audit.md` §2.2) |

Example (design sketch — the real code is written in Step 8):

```sql
create function private.is_member(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.organizations o on o.id = m.organization_id
    join public.profiles p      on p.id = m.user_id
    where m.organization_id = org
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and o.status = 'active'
      and p.status = 'active'
  );
$$;

revoke all on function private.is_member(uuid) from public, anon;
grant execute on function private.is_member(uuid) to authenticated;
```

### 3.3 Avoiding infinite recursion on `memberships`

If the `select` policy on `memberships` said "you may see memberships of organizations where you have a membership" **using a normal query on `memberships`**, PostgreSQL would have to check the same policy again for that inner query, and again… → error "infinite recursion detected in policy".

Solution: the policy calls `private.is_member(org)`, a `security definer` function. Inside the function RLS is **not** applied (it runs as the table owner), so there is no loop. The function only answers yes/no for the **current user**, so it leaks nothing.

## 4. Security definer RPC functions (the "only doors" for sensitive changes)

Every such function in `public`:

1. has `security definer` + `set search_path = ''`,
2. starts by checking `auth.uid()` is not null,
3. checks permissions itself with the helpers (e.g. `private.can_write(org, array['owner','admin','accountant'])`),
4. loads every record **by ID together with the organization** and locks it when money is involved (`for update`),
5. validates every input again (the server already did with Zod — this is the second check),
6. raises clear, safe error codes (e.g. `INVOICE_NOT_DRAFT`) that the server translates to friendly messages,
7. writes the activity log,
8. has `execute` revoked from `anon` and granted only to `authenticated`.

| Function | Allowed for | Step |
|---|---|---|
| `create_organization(...)` | Any verified user (limit D-37) | 10 |
| `get_invitation_preview(token)` | Anyone (returns only safe fields) | 11 |
| `accept_invitation(token)` | Verified user whose email matches | 11 |
| `change_member_role(membership, role)` | OWNER (anyone but self), ADMIN (not OWNER, not self, not to OWNER) | 11 |
| `set_member_status(membership, status)` | same as above | 11 |
| `transfer_ownership(org, membership)` | OWNER only; target must be an active non-client member | 11 |
| `leave_organization(org)` | Any member except OWNER / CLIENT | 11 |
| `issue_invoice(invoice)` | OWNER, ADMIN, ACCOUNTANT | 15 |
| `void_invoice(invoice, reason)` | OWNER, ADMIN, ACCOUNTANT | 15 |
| `duplicate_invoice(invoice)` | OWNER, ADMIN, ACCOUNTANT | 15 |
| `record_payment(...)` / `reverse_payment(payment, reason)` | OWNER, ADMIN, ACCOUNTANT | 16 |
| `void_expense(expense, reason)` | OWNER, ADMIN, ACCOUNTANT | 17 |
| `mark_notifications_read(ids)` / `mark_all_notifications_read(org)` | The recipient | 19 |
| `get_my_organizations()` | Any logged-in user (own memberships incl. suspended orgs: name, slug, status, role) | 10 |
| `change_organization_currency(org, currency)` | OWNER, only before the first issued invoice | 10 |
| `get_my_subscription(org)` | OWNER (full, without notes), ADMIN (plan, limits, usage) | 22 |
| Platform functions (`set_organization_status`, `activate_subscription`, `void_subscription_payment`, `change_plan`, `set_account_status`) | PLATFORM_ADMIN | 22 |

## 5. RLS strategy per table

Abbreviations: **M(org)** = `is_member(org)`; **R(org, […])** = `has_role(org, [...])`; **W(org, […])** = `can_write(org, [...])`; **PA** = `is_platform_admin()`; **CC** = `client_customer_id(organization_id)`; **ME** = `(select auth.uid())`.
"Fn only" = no policy; changes only through the RPC functions in §4.

### 5.1 `organizations`

| Action | Rule |
|---|---|
| select | `M(id)` **or** `PA` **or** the user has a membership (any status) in it whose org is suspended — so the suspended page can show the name. (Suspended orgs expose only name/slug/status through a function `get_my_organizations()`; business tables stay closed because `is_member` requires `active`.) |
| insert | Fn only (`create_organization`) |
| update | `W(id, [owner, admin])`, column grants: `name`, `timezone`, `logo_path`. `status`, `slug`, `suspended_reason` only by platform functions. `currency` only by a function that checks "no issued invoice yet" (OWNER). |
| delete | none (D-24 permanent deletion by PLATFORM_ADMIN via admin client) |

### 5.2 `memberships`

| Action | Rule |
|---|---|
| select | own row (`user_id = ME`) **or** `R(organization_id, [owner, admin, manager, accountant])` (team list for OWNER/ADMIN/MANAGER; ACCOUNTANT needs names shown on tasks but has no Team page) **or** (`employee`) rows of members sharing a project with me **or** `PA` (counts only, via platform function) |
| insert | Fn only (`create_organization`, `accept_invitation`) |
| update | Fn only (`change_member_role`, `set_member_status`, `transfer_ownership`, `leave_organization`) |
| delete | none (disable instead) |
| extra | Trigger: nobody changes their own `role`/`status`; the OWNER row can only change inside `transfer_ownership`; partial unique index = max one OWNER |

A CLIENT sees only their own membership row.

### 5.3 `profiles`

| Action | Rule |
|---|---|
| select | own row, **or** profiles of people who share an organization with me **and** whom my role may see (same rule as memberships select), **or** `PA` |
| insert | none (trigger `handle_new_user` on signup) |
| update | own row only; column grants: `full_name`, `phone`, `last_organization_id` (status only by platform function) |
| delete | none |

### 5.4 `invitations`

| Action | Rule |
|---|---|
| select | `R(organization_id, [owner, admin])`. The invitee does **not** read this table; they use `get_invitation_preview(token)` |
| insert | `W(organization_id, [owner, admin])` with check: `role <> 'owner'`, `invited_by = ME` (forced), status `pending` |
| update | `W(organization_id, [owner, admin])`, column grants: `status` (only to `cancelled`, checked by trigger), `token_hash`, `expires_at`, `last_sent_at`, `send_count` (resend). Accepting = Fn only |
| delete | none |
| extra | `token_hash` column is **not granted for select** to anyone — even OWNER/ADMIN cannot read it |

### 5.5 `organization_settings`

| Action | Rule |
|---|---|
| select | `M(organization_id)` (clients need name/address for invoices; nothing secret is stored here) |
| insert | Fn only |
| update | `W(organization_id, [owner, admin])` |
| delete | none |

### 5.6 `customers`

| Action | Rule |
|---|---|
| select | `R(org, [owner, admin, manager, accountant])` **or** (`R(org,[client])` and `id = CC`) **or** (`R(org,[employee])` and the customer has a project I'm a member of — D-05) |
| insert | `W(org, [owner, admin, manager, accountant])` (accountant per D-08) |
| update | `W(org, [owner, admin, manager, accountant])`; archiving (`archived_at`) only owner/admin/manager (trigger) |
| delete | none (archive) |

Employees and clients read customers through the same table, but the app only selects the basic columns; nothing internal is stored in `customers` (§1.2 of `04-database.md`).

### 5.7 `projects` and `project_members`

| Table / action | Rule |
|---|---|
| projects select | `R(org, [owner, admin, manager, accountant])` **or** (`employee` and `is_project_member(org, id)`) **or** (`client` and `customer_id = CC`) |
| projects insert / update | `W(org, [owner, admin, manager])` |
| projects delete | none (archive) |
| project_members select | `R(org, [owner, admin, manager, accountant])` or (`employee` and it is a project I'm a member of) |
| project_members insert / delete | `W(org, [owner, admin, manager])` |

### 5.8 `tasks` and `task_comments`

| Table / action | Rule |
|---|---|
| tasks select | `R(org, [owner, admin, manager, accountant])` **or** (`employee` and `assignee_membership_id = my_membership_id(org)`) **or** (`client` and `clients_see_tasks(org)` and the task's project has `customer_id = CC`) |
| tasks insert | `W(org, [owner, admin, manager])` (D-07: employees cannot) |
| tasks update | `W(org, [owner, admin, manager])` **or** (`W(org, [employee])` and I am the assignee — trigger allows only `status` to change) |
| tasks delete | none (archive) |
| task_comments select | anyone who can select the task, **except clients** |
| task_comments insert | `W(org, [owner, admin, manager])` or (employee and assignee of the task); `author_user_id` forced |
| task_comments update | own comment only (`author_user_id = ME`), column grant `body` |
| task_comments delete | own comment, or `W(org, [owner, admin])` |

Clients selecting tasks can read all columns of the task row — so task rows must contain nothing internal when the setting is on (the UI warns when turning it on).

### 5.9 `services_products`

| Action | Rule |
|---|---|
| select | `R(org, [owner, admin, manager, accountant])` |
| insert / update | `W(org, [owner, admin, accountant])` |
| delete | none (archive) |

### 5.10 `invoices` and `invoice_items`

| Table / action | Rule |
|---|---|
| invoices select | `R(org, [owner, admin, accountant, manager])` (manager per D-02) **or** (`client` and `customer_id = CC` and `status <> 'draft'`) |
| invoices insert | `W(org, [owner, admin, accountant])`, check `status = 'draft'` |
| invoices update | `W(org, [owner, admin, accountant])` **and** `status = 'draft'` (using + with check). Column grants: customer, project, dates, notes, terms. Totals/status/number: triggers and functions only |
| invoices delete | `W(org, [owner, admin, accountant])` **and** `status = 'draft'` |
| invoice_items select | same as the parent invoice (via `exists` on invoices, which applies invoices' RLS) |
| invoice_items insert / update / delete | `W(org, [owner, admin, accountant])` **and** parent invoice is `draft` (also enforced by trigger). Calculated columns not granted |

Issue / void / duplicate: Fn only (§4).

### 5.11 `payments`

| Action | Rule |
|---|---|
| select | `R(org, [owner, admin, accountant, manager])` **or** (`client` and `customer_id = CC`) |
| insert / update | Fn only (`record_payment`, `reverse_payment`) |
| delete | none, ever (D-32) |

### 5.12 `expense_categories` and `expenses`

| Table / action | Rule |
|---|---|
| select | `R(org, [owner, admin, accountant])` (MANAGER, EMPLOYEE, CLIENT: none — D-02) |
| insert / update | `W(org, [owner, admin, accountant])`. Expense `status` changes only through `void_expense` |
| delete | none (archive categories, void expenses) |

### 5.13 `documents` (and Storage)

| Action | Rule |
|---|---|
| select | You can see the document if you can see the record it is attached to, by role (matrix §3.9 in `02-roles-permissions.md`): OWNER/ADMIN all; MANAGER all except expense documents; ACCOUNTANT customer/invoice/expense documents + project/task documents (view, D-03); EMPLOYEE documents of tasks assigned to them and projects they are a member of; CLIENT only `visible_to_client = true` **and** linked to their customer (customer itself, their projects, their non-draft invoices, and tasks of their projects if `clients_see_tasks`) |
| insert | Done by the `confirmUpload` Server Action after the upload check (`10-documents.md` §5): `W(org, roles allowed to upload to that kind of record — matrix §3.9)` **and** the linked record is visible to the user (checked with `exists` on the linked table, whose RLS applies); `uploaded_by` forced |
| update | `W(org, [owner, admin, manager, accountant])`, column grants: `visible_to_client`, `file_name` |
| delete | `W(org, [owner, admin])` or own upload (`uploaded_by = ME`) with upload rights |

Storage policies are tied to this table: a file can be downloaded only if the user can `select` a `documents` row with that exact `storage_path` (details in `10-documents.md`).

### 5.14 `notifications`

| Action | Rule |
|---|---|
| select | `recipient_user_id = ME` **and** (`M(org)` so a removed member stops seeing that org's notifications, **or** `type = 'invitation_received'` — `11-notifications-audit.md` §1.2) |
| insert | Fn/trigger only |
| update | Fn only (`mark_notifications_read`) — only `read_at` changes |
| delete | none (automatic clean-up, D-27) |

### 5.15 `activity_logs`

| Action | Rule |
|---|---|
| select | `R(organization_id, [owner, admin])`; rows with `organization_id is null` (platform events): `PA`. PLATFORM_ADMIN reads tenant logs only if D-01 allows |
| insert | trigger / functions only (the audit trigger function is `security definer`) |
| update / delete | **none**; `update`, `delete`, `truncate` privileges revoked from `authenticated` and `anon` |

### 5.16 Platform tables

| Table | select | insert / update / delete |
|---|---|---|
| `platform_admins` | own row, or `PA` | none (SQL in dashboard only) |
| `plans` | any logged-in user: `is_active` plans; `PA`: all | `PA` |
| `subscriptions` | `PA`. Organizations read their plan through `get_my_subscription(org)` (OWNER: full info without `notes`; ADMIN: plan, limits and usage) | Fn only (platform functions) |
| `subscription_payments` | `PA`; OWNER of that org (via function, without internal notes) | Fn only (`PA`) |
| `platform_settings` | `PA` (public values like `signups_enabled` read by the server via a function) | `PA` |
| `platform_announcements` | published + current: any user with an active non-client membership, or `PA` | `PA` |
| `number_sequences` | none | none (only `issue_invoice`) |

## 6. How each attack is stopped

| Attack | How it is stopped |
|---|---|
| **Organization A reads Organization B** | Every business policy starts with a helper that requires an active membership in the row's `organization_id`. A user of A has no membership in B → zero rows. Composite foreign keys stop cross-organization links. Server loads data by `organization_id` of the URL's slug **after** checking membership. |
| **Unauthorized URL access** (`/app/org-b/invoices`, `/platform`) | proxy: must be logged in. Layout: `requireMembership('org-b')` → "No access" page. Page: role check (e.g. employee opening `/invoices` → "No access"). Even if these were skipped, RLS returns nothing. |
| **ID manipulation** (changing `/invoices/<id>` to another ID) | The server queries `where id = :id and organization_id = :currentOrg`; RLS additionally hides rows of other orgs/customers. Result: "Not found" (we show 404, not "forbidden", so the attacker cannot even learn that the ID exists). UUIDs cannot be guessed. |
| **Client A sees Client B** | Client policies compare `customer_id` with `client_customer_id(org)`, taken from **their membership in the database**, not from the URL or the browser. |
| **Employee uses admin functions** | Buttons hidden; Server Action role check refuses; RLS write policies require `owner/admin/…`; RPC functions check roles themselves. |
| **Direct API calls with the public (publishable) key** | The key only identifies the project; it gives no rights. Without login → `anon` → no policies → nothing. With login → the same RLS as the website. Helper functions are in the unexposed `private` schema; RPC functions check permissions themselves. |
| **User changes their own role** | No update policy on `memberships`; role changes only via `change_member_role`, which refuses `membership.user_id = auth.uid()`; a trigger blocks it again; roles are never read from `user_metadata`. |
| **User changes `organization_id`, totals, status, `created_by`** | Column grants do not include them; triggers force/recalculate them. |
| **Disabled member keeps an open tab** | `is_member` requires `status = 'active'` → next request returns nothing; server shows "No access". |
| **Suspended organization** | `is_member` requires the organization to be `active` → all business data closed at database level. |

## 7. How RLS is tested

- SQL test files in `supabase/tests/` using **pgTAP** (a testing tool for PostgreSQL that Supabase supports; run with `npx supabase test db`).
- Each test creates two organizations with users of every role, then **acts as** a user (sets their ID the way Supabase does) and checks what they can see/change. Minimum tests (more in `16-security-performance-testing.md`):
  1. User of org A selects customers/invoices/documents of org B → 0 rows.
  2. User of org A inserts a customer with `organization_id` = B → refused.
  3. Client A selects invoices of customer B (same org) → 0 rows; drafts of own customer → 0 rows.
  4. Employee selects a task not assigned to them → 0 rows; updates a task title → refused.
  5. Member updates own `memberships.role` → refused; ADMIN changes OWNER → refused.
  6. Not logged in (`anon`) selects anything → 0 rows.
  7. Disabled member / suspended organization → 0 rows.
  8. Nobody can update or delete `activity_logs`.

## 8. Decisions for this file (answered 2026-09-23 — "use recommendation")

None new. Depends on: D-01, D-02, D-03, D-05, D-06, D-07, D-08, D-25, D-32.
