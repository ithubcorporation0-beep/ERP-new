# 04 — Database

> The database is **PostgreSQL** (a very reliable database) hosted by **Supabase**.
> A **table** is like an Excel sheet; a **column** is one field; a **row** is one record.
> Nothing in this file is created yet. Tables are created later with migration files (see §7 for which step creates which table).

---

## 1. Design rules (apply to every table)

| Rule | What it means | Why |
|---|---|---|
| **UUID primary keys** | Every row's ID is a random `uuid` (like `3f2a…`). Exception: `activity_logs` uses a counting number (faster for a table that only grows). | IDs cannot be guessed or counted ("invoice 1, 2, 3…"). |
| **`organization_id uuid not null`** on every business table | Every business row says which organization owns it. | Tenant isolation: RLS and every query filter on it. |
| **`organization_id` can never change** | A trigger blocks changing it after insert. | A record can never be "moved" into another organization. |
| **Uniqueness per organization** | Example: `unique (organization_id, invoice_number)`. | Two organizations may both have `INV-2026-0001`. |
| **Same-organization links** | Composite foreign keys (§2.3). | A record can never point at another organization's record. |
| **Money = `numeric(12,2)`** | Exact decimal numbers up to 9,999,999,999.99. Never `float` (floats make rounding errors like 0.1 + 0.2 = 0.30000000000000004). | Correct money. |
| **Status values = `text` + check constraint** | Example: `status text check (status in ('draft','sent',…))`. | Easy to add a new status later with a small migration (Postgres "enum" types are hard to change). |
| **Timestamps** | `created_at timestamptz default now()`, `updated_at timestamptz` (set by trigger). Business dates (issue date, payment date…) use `date`. | `timestamptz` stores exact moments in UTC; dates are shown in the organization's timezone. |
| **`created_by`** | `uuid` → `profiles.id`, **forced** to the logged-in user by a trigger (whatever the browser sends is ignored). | Honest "who created this". |
| **Names** | Tables and columns in `snake_case`, table names plural. Roles stored lowercase (`owner`), shown uppercase in docs/UI (`OWNER`). | Postgres convention. |
| **RLS on every table** | Policies are written in the same migration that creates the table (`06-authorization-rls.md`). | No table is ever unprotected, even for a minute. |
| **Indexes** | On `organization_id`, on every foreign key, and on columns used for filters/sorting. | Fast lists even with many organizations. |
| **Length limits** | Check constraints on text length (e.g. names ≤ 200 characters), matched by Zod on the server. | Stops junk and huge inputs. |

### 1.1 Soft-delete strategy (decided)

"Soft delete" = hiding a record instead of really removing it. We do **not** use a general `deleted_at` column on every table, because every query and every RLS policy would then have to remember `deleted_at is null`, and one forgotten filter shows "deleted" data. Instead each kind of record gets the rule that fits it:

| Kind of record | How it is "deleted" | Tables |
|---|---|---|
| Master / work records | **Archive**: `archived_at timestamptz null`. Archived rows are hidden from normal lists by default, can be shown with an "Archived" filter and restored. | `customers`, `projects`, `tasks`, `services_products`, `expense_categories` |
| Money records | **Never deleted.** Invoices: drafts may be deleted; issued invoices are **voided**. Payments are **reversed**. Expenses are **voided**. | `invoices`, `payments`, `expenses`, `subscription_payments` |
| People links | **Disabled**, never deleted (their name must stay on old tasks and logs). | `memberships`, `profiles` (status) |
| Invitations | Status `cancelled` / `expired` / `accepted`. | `invitations` |
| Simple links and small items | **Real delete** (logged in `activity_logs`). | `project_members`, `task_comments`, `documents` (row + file) |
| Logs | Never edited or deleted by users. | `activity_logs` |
| Organizations | `pending_deletion`, then permanent removal by PLATFORM_ADMIN after 30 days (D-24). | `organizations` |

Foreign keys between business tables use `on delete restrict` (the database refuses to delete a customer who still has projects or invoices), which fits the archive rule.

### 1.2 Rule for rows that clients can see

RLS works per **row**, not per column. If a CLIENT may read a row, they can technically read **every column** of it (for example by calling the database directly with the public key). Therefore:

- Tables that clients can read (`customers` own row, `projects`, `invoices`, `invoice_items`, `payments`, `documents` marked visible, `tasks` if D-06 is on) **must not contain internal-only columns**. Fields such as `projects.description`, `payments.notes` are labelled in the UI as "visible to the client".
- Internal-only information (project budget, internal notes) must live in a **separate table** that clients cannot read. This is why project budget is postponed (D-18).

---

## 2. Relationships

### 2.1 Diagram

```
PLATFORM
  platform_admins ── profiles
  plans ── subscriptions ── organizations
           subscription_payments ── organizations
  platform_settings,  platform_announcements

PEOPLE
  Clerk user (login, D-62) ──1:1── profiles   (profiles.id = Clerk user id)
  organizations ──< memberships >── profiles        (one row per person per organization)
  organizations ──< invitations                     (becomes a membership when accepted)
  organizations ──1:1── organization_settings

WORK
  organizations ──< customers ──< projects ──< tasks ──< task_comments
                        ▲            │            └── assignee → memberships
                        │            └──< project_members >── memberships
                        └── memberships.customer_id   (CLIENT login linked to one customer)

MONEY
  organizations ──< services_products
  customers ──< invoices ──< invoice_items ── (optional) services_products
                    │   └── (optional) project
                    └──< payments
  organizations ──< expense_categories ──< expenses ── (optional) project
  organizations ──< number_sequences        (invoice number counters)

FILES & SYSTEM
  documents → exactly one of: customer | project | task | invoice | expense
  notifications → recipient (profiles)
  activity_logs → organization (or platform), actor (profiles)
```

`──<` means "one to many" (one customer has many projects).

### 2.2 Short version (as in the brief)

```
Organization → Membership → User (profile)
Organization → Customer → Project → Task → Assigned employee (membership)
Organization → Customer → Invoice → Invoice items
                                  → Payments
Organization → Expense → Expense category
Customer ← Client membership (client login)
```

### 2.3 How links stay inside the same organization

A normal foreign key only checks "this customer ID exists". It does not check "this customer belongs to the **same** organization". Someone could otherwise create an invoice in organization A pointing to a customer of organization B.

**Method: composite foreign keys.**

1. Every business table gets an extra uniqueness rule: `unique (organization_id, id)`.
2. Every link uses **both** columns:
   ```sql
   foreign key (organization_id, customer_id)
     references customers (organization_id, id)
   ```
3. The database now only accepts a link if the linked record has the **same `organization_id`**. This is checked by PostgreSQL itself on every insert/update, so no code bug can break it.
4. For optional links (e.g. `projects.customer_id` may be empty), the check simply does not apply when the value is empty — which is what we want.

On top of that, RLS insert/update policies check that the user is a member of that `organization_id` (`06-authorization-rls.md`).

---

## 3. Tables in V1 — decision list

| Group | Table | V1? | Note |
|---|---|---|---|
| Platform | `organizations` | ✅ | |
| | `plans` | ✅ | Platform-wide (no `organization_id`). |
| | `subscriptions` | ✅ | One row per organization = current plan state. |
| | `subscription_payments` | ✅ (added) | Records manual payments for the SaaS subscription (manual billing needs a record of who paid what). |
| | `platform_admins` | ✅ | |
| | `platform_settings` | ✅ | |
| | `platform_announcements` | ✅ (added) | The brief asks for platform announcements; they are not per-user notifications, so they get their own table. |
| People | `profiles` | ✅ | |
| | `memberships` | ✅ | |
| | `invitations` | ✅ | |
| Business | `customers` | ✅ | |
| | `customer_contacts` | ❌ | D-16: V1 keeps one contact person on the customer. |
| | `projects` | ✅ | |
| | `project_members` | ✅ | Needed so employees see "my projects". |
| | `tasks` | ✅ | |
| | `task_comments` | ✅ | Main way employees and managers talk about a task. |
| | `services_products` | ✅ | **One table** with `item_type` = service/product. Separate tables are only useful with stock control (D-19), which V1 does not have. |
| | `invoices`, `invoice_items` | ✅ | |
| | `payments` | ✅ | |
| | `expense_categories`, `expenses` | ✅ | |
| | `documents` | ✅ | |
| System | `organization_settings` | ✅ | |
| | `number_sequences` | ✅ | |
| | `notifications` | ✅ | |
| | `activity_logs` | ✅ | |

Total: **25 tables** in V1, plus one small internal table `private.rate_limits` (attempt counters for rate limiting — D-53; lives in the unexposed `private` schema, no user access, created in Step 11, where invitations are its first user).

---

## 4. Table details

Column table legend: **Req** = required (`not null`). "Forced" = set by the database, browser value ignored.
Unless a table lists its own timestamp columns, it has `created_at` and `updated_at`; they are mentioned once here and not repeated. `updated_at` is set by the shared trigger `set_updated_at()`.

### 4.1 Platform tables

#### `organizations`
One business (tenant).

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK, default `gen_random_uuid()` |
| name | text | ✅ | 2–100 chars |
| slug | text | ✅ | Web name used in URLs (`/app/wajid-marble`). Lowercase letters, digits, single hyphens, 3–40 chars. **Unique globally.** Reserved words blocked (`app`, `platform`, `api`, `admin`, `login`, `signup`, `onboarding`, `settings`, …). Change rules: D-28. |
| status | text | ✅ | `active` (default) · `suspended` · `pending_deletion` |
| suspended_reason | text | | Shown on the suspended page (set by PLATFORM_ADMIN) |
| currency | char(3) | ✅ | ISO code, default `PKR`. Locked after the first invoice is issued (D-12). |
| timezone | text | ✅ | Default `Asia/Karachi` |
| logo_path | text | | Path of logo file in storage (`10-documents.md` §9) |
| deletion_requested_at | timestamptz | | Set when OWNER requests deletion (D-24) |
| created_by | uuid | ✅ | → `profiles.id`, forced |

Indexes: unique `lower(slug)`; `status`.
Status meanings: `active` = normal; `suspended` = blocked by PLATFORM_ADMIN (nobody in the org can open data); `pending_deletion` = hidden, waiting for permanent deletion.
Delete: never by users (D-24).

#### `plans`
Subscription plans. Platform-wide, **no `organization_id`** (not a business table).

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| code | text | ✅ | Unique, e.g. `trial`, `basic`, `pro` |
| name | text | ✅ | Display name |
| description | text | | |
| price_monthly | numeric(12,2) | ✅ | ≥ 0 |
| price_yearly | numeric(12,2) | | Optional yearly price |
| currency | char(3) | ✅ | Default `PKR` |
| max_users | integer | | Empty = unlimited. Counts active non-client memberships. Numbers: D-47 |
| max_clients | integer | | Empty = unlimited. Counts active client memberships |
| max_customers | integer | | Empty = unlimited |
| max_storage_mb | integer | | Empty = unlimited |
| is_public | boolean | ✅ | Shown on pricing page; default true |
| is_active | boolean | ✅ | Can be chosen for new subscriptions; default true |
| sort_order | integer | ✅ | Default 0 |

Delete: plans are deactivated (`is_active = false`), never deleted while subscriptions use them.

#### `subscriptions`
The **current** plan state of each organization (exactly one row per organization). History is kept in `subscription_payments` and `activity_logs`.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | → organizations. **Unique** (one row per org) |
| plan_id | uuid | ✅ | → plans |
| status | text | ✅ | `trialing` · `active` · `expired` · `cancelled` |
| trial_ends_at | timestamptz | | Set when the trial starts (trial length D-48) |
| current_period_start | date | | Set when PLATFORM_ADMIN activates/extends |
| current_period_end | date | | Access paid until this date |
| notes | text | | PLATFORM_ADMIN's internal note (not visible to the organization) |
| updated_by | uuid | | → profiles, forced |

Indexes: `organization_id` (unique), `plan_id`, `(status, current_period_end)` to find subscriptions expiring soon.
Why `notes` is safe here: organizations do not read this table directly; they see their plan through a database function that returns only safe fields (details in `12-billing-subscriptions.md`).

#### `subscription_payments`
Manual payments an organization made to the platform (bank transfer, JazzCash, Easypaisa…).

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | → organizations |
| plan_id | uuid | ✅ | → plans (plan paid for) |
| amount | numeric(12,2) | ✅ | > 0 |
| currency | char(3) | ✅ | |
| method | text | ✅ | `bank_transfer` · `jazzcash` · `easypaisa` · `cash` · `other` |
| reference | text | | Transaction ID / slip number |
| paid_on | date | ✅ | |
| period_start, period_end | date | ✅ | Period this payment covers |
| status | text | ✅ | `recorded` · `void` |
| void_reason | text | | Required when voided |
| recorded_by | uuid | ✅ | → profiles (PLATFORM_ADMIN), forced |

Indexes: `(organization_id, paid_on)`.

#### `platform_admins`
Who is PLATFORM_ADMIN.

| Column | Type | Req | Notes |
|---|---|---|---|
| user_id | uuid | ✅ | PK, → profiles, on delete cascade |
| note | text | | e.g. "founder" |
| created_at | timestamptz | ✅ | |

Rows are added **only by SQL in the Supabase dashboard** (no insert/update/delete policy exists, so the website cannot add platform admins).

#### `platform_settings`
Simple key → value settings for the whole platform.

| Column | Type | Req | Notes |
|---|---|---|---|
| key | text | ✅ | PK, e.g. `signups_enabled`, `default_trial_days`, `support_contact` |
| value | jsonb | ✅ | The setting value (jsonb = flexible structured data) |
| description | text | | What it does |
| updated_by | uuid | | → profiles, forced |

#### `platform_announcements`
Messages from the platform to organizations (e.g. "maintenance on Sunday").

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| title | text | ✅ | ≤ 150 chars |
| body | text | ✅ | ≤ 5000 chars (plain text, no HTML) |
| level | text | ✅ | `info` · `warning` · `critical` |
| starts_at | timestamptz | ✅ | Default now |
| ends_at | timestamptz | | Empty = until unpublished |
| is_published | boolean | ✅ | Default false |
| created_by | uuid | ✅ | forced |

Index: `(is_published, starts_at)`. Read by business users (not clients — D-30).

### 4.2 People tables

#### `profiles`
One row per user account. Logins are handled by Clerk (D-62): our server creates/updates the row right after login with the name and email it reads from Clerk's server.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | text | ✅ | PK, **the Clerk user id** (e.g. `user_2abc…`). All columns that point to a person (`user_id`, `created_by`, `invited_by`, …) are therefore `text` |
| email | text | ✅ | Copied from Clerk by the server at every login; users cannot edit it here |
| full_name | text | ✅ | 1–100 chars |
| phone | text | | |
| avatar_path | text | | Profile photo in storage — not used in V1 (D-45), kept for later |
| status | text | ✅ | `active` (default) · `disabled` (only PLATFORM_ADMIN can change) |
| disabled_reason | text | | |
| last_organization_id | uuid | | → organizations, on delete set null. Remembers the last organization opened (convenience only, never used for security) |

Indexes: unique `lower(email)`.
Column grants let users change only `phone` and `last_organization_id`; name and email come from Clerk, status only from PLATFORM_ADMIN.
**There is no `role` column here on purpose.** Roles live only in `memberships` and `platform_admins`.

#### `memberships`
Connects a person to an organization with a role.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | → organizations |
| user_id | uuid | ✅ | → profiles |
| role | text | ✅ | `owner` · `admin` · `manager` · `accountant` · `employee` · `client` |
| status | text | ✅ | `active` (default) · `disabled` |
| customer_id | uuid | | Only for `client`. Composite FK `(organization_id, customer_id) → customers` (added in Step 12 when `customers` exists) |
| job_title | text | | Display only, e.g. "Site supervisor" |
| invited_by | uuid | | → profiles |
| disabled_at | timestamptz | | |
| disabled_by | uuid | | → profiles |

Constraints:
- `unique (organization_id, user_id)` — one role per person per organization.
- `unique (organization_id, id)` — for composite foreign keys.
- `check ((role = 'client') = (customer_id is not null))` — a client **must** have a customer; other roles **must not**.
- Partial unique index `on memberships (organization_id) where role = 'owner'` — **at most one owner**. "At least one owner" is protected by a trigger: the owner row cannot be demoted, disabled or deleted except inside the `transfer_ownership()` database function, which changes both rows in one transaction.
- A trigger blocks any user from changing **their own** `role` or `status`.

Indexes: `user_id` (find "my organizations" at login), `(organization_id, role)`, `(organization_id, customer_id)`.
Delete: never — disabled instead.

#### `invitations`
An invite to join an organization with a role.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | → organizations |
| email | text | ✅ | Stored lowercase |
| role | text | ✅ | Any role **except** `owner` |
| customer_id | uuid | | Required when role = `client`; composite FK (added in Step 12) |
| token_hash | text | ✅ | **Unique.** SHA-256 hash of a long random token. The real token only appears in the invite link, so even someone reading the database cannot use an invite. |
| status | text | ✅ | `pending` (default) · `accepted` · `cancelled` · `expired` |
| expires_at | timestamptz | ✅ | created_at + 7 days (D-23). A pending invite past this time is treated as expired. |
| invited_by | uuid | ✅ | → profiles, forced |
| accepted_by | uuid | | → profiles |
| accepted_at, cancelled_at | timestamptz | | |
| last_sent_at | timestamptz | | For "resend" |
| send_count | integer | ✅ | Default 1 — used to limit resends |

Constraints: partial unique `(organization_id, lower(email)) where status = 'pending'` (no duplicate open invites); check `role <> 'owner'`; check `(role = 'client') = (customer_id is not null)`.
Indexes: `organization_id`, `lower(email)`.
`token_hash` is **never** shown in the app or written to `activity_logs`.

### 4.3 Business tables

All tables in this section have: `organization_id uuid not null → organizations`, `unique (organization_id, id)`, index on `organization_id`, `created_by` forced (where listed), `created_at`, `updated_at`.

#### `customers`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| name | text | ✅ | Company or person name, 1–200 chars |
| contact_person | text | | Main contact (D-16) |
| email | text | | |
| phone | text | | |
| address | text | | |
| city | text | | |
| tax_number | text | | Free text (e.g. NTN) — no validation rule assumed |
| notes | text | | Visible to the linked CLIENT (§1.2) |
| archived_at | timestamptz | | Archive (§1.1) |
| created_by | uuid | ✅ | forced |

Indexes: `(organization_id, lower(name))` for search/sort; `(organization_id, archived_at)`.
No uniqueness on name (two customers may have the same name).

#### `projects`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| customer_id | uuid | | Composite FK → customers. Empty = internal project (D-17) |
| name | text | ✅ | 1–200 chars |
| description | text | | Visible to the linked CLIENT |
| status | text | ✅ | `planned` · `active` (default) · `on_hold` · `completed` · `cancelled` |
| start_date | date | | |
| due_date | date | | Check `due_date >= start_date` |
| completed_at | timestamptz | | Set by trigger when status becomes `completed` |
| archived_at | timestamptz | | |
| created_by | uuid | ✅ | forced |

Indexes: `(organization_id, status)`, `(organization_id, customer_id)`, `(organization_id, due_date)`.
No budget column in V1 (D-18).

#### `project_members`
Which staff members work on which project.

| Column | Type | Req | Notes |
|---|---|---|---|
| organization_id | uuid | ✅ | |
| project_id | uuid | ✅ | Composite FK → projects, on delete cascade |
| membership_id | uuid | ✅ | Composite FK → memberships |
| added_by | uuid | ✅ | forced |
| created_at | timestamptz | ✅ | |

PK: `(project_id, membership_id)`. Index: `(organization_id, membership_id)`.
Trigger: a `client` membership cannot be added.
When a task in a project is assigned to someone, that person is **automatically added** here (so they can see the project of their task).

#### `tasks`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| project_id | uuid | | Composite FK → projects. Empty = general task (D-17) |
| title | text | ✅ | 1–200 chars |
| description | text | | Visible to clients only if D-06 is on and the task has a project of theirs |
| status | text | ✅ | `todo` (default) · `in_progress` · `blocked` · `done` · `cancelled` |
| priority | text | ✅ | `low` · `medium` (default) · `high` · `urgent` |
| assignee_membership_id | uuid | | Composite FK → memberships. One assignee in V1. Must be an active, non-client member (trigger) |
| due_date | date | | |
| completed_at | timestamptz | | Set by trigger when status becomes `done`, cleared if reopened |
| archived_at | timestamptz | | |
| created_by | uuid | ✅ | forced |

Indexes: `(organization_id, status)`, `(organization_id, assignee_membership_id, status)` (for "My tasks"), `(organization_id, project_id)`, `(organization_id, due_date)`.
Trigger: an EMPLOYEE may change only `status` on their own tasks (all other columns blocked for that role).

#### `task_comments`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| task_id | uuid | ✅ | Composite FK → tasks, on delete cascade |
| author_user_id | uuid | ✅ | → profiles, forced to the logged-in user |
| body | text | ✅ | 1–5000 chars, plain text (shown safely, no HTML) |
| edited_at | timestamptz | | Set when the author edits |

Index: `(organization_id, task_id, created_at)`.
Delete: real delete (author, or OWNER/ADMIN), logged.

#### `services_products`
The price list.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| item_type | text | ✅ | `service` · `product` |
| name | text | ✅ | 1–200 chars |
| description | text | | Copied to the invoice line when chosen |
| sku | text | | Optional item code. Unique per organization when filled: `unique (organization_id, lower(sku)) where sku is not null` |
| unit | text | ✅ | e.g. `unit`, `hour`, `sq ft`, `piece`. Default `unit` |
| unit_price | numeric(12,2) | ✅ | ≥ 0 |
| tax_rate | numeric(5,2) | | Percent 0–100. Empty = use organization default (D-10) |
| archived_at | timestamptz | | |
| created_by | uuid | ✅ | forced |

Indexes: `(organization_id, item_type)`, `(organization_id, lower(name))`.
Choosing an item on an invoice **copies** name, unit, price and tax into the invoice line, so changing the price list later never changes old invoices.

#### `invoices`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| customer_id | uuid | ✅ | Composite FK → customers |
| project_id | uuid | | Composite FK → projects (must belong to the same customer — trigger) |
| invoice_number | text | | **Empty while draft.** Given when the invoice is issued (D-13). `unique (organization_id, invoice_number)` |
| status | text | ✅ | `draft` (default) · `sent` · `partially_paid` · `paid` · `void` |
| issue_date | date | ✅ | Default today (org timezone) |
| due_date | date | ✅ | Default issue_date + setting; check `due_date >= issue_date` |
| currency | char(3) | ✅ | Copied from the organization, forced (D-12) |
| subtotal | numeric(12,2) | ✅ | Sum of line subtotals — **calculated by trigger** |
| discount_total | numeric(12,2) | ✅ | Sum of line discounts — calculated (D-11) |
| tax_total | numeric(12,2) | ✅ | Sum of line taxes — calculated (D-10) |
| total | numeric(12,2) | ✅ | subtotal − discount_total + tax_total — calculated |
| amount_paid | numeric(12,2) | ✅ | Sum of `completed` payments — calculated by payment trigger |
| balance_due | numeric(12,2) | ✅ | **Generated column** = total − amount_paid (always correct automatically) |
| bill_to | jsonb | | Snapshot of customer name/address/tax number taken **when issued**, so later edits to the customer do not change old invoices |
| notes | text | | Printed on invoice (visible to client) |
| terms | text | | Printed on invoice |
| sent_at | timestamptz | | |
| sent_by | uuid | | |
| voided_at | timestamptz | | |
| voided_by | uuid | | |
| void_reason | text | | Required when voided |
| created_by | uuid | ✅ | forced |

Checks: all money ≥ 0; `amount_paid <= total` (D-14); `invoice_number is not null` when status ≠ `draft`.
**"Overdue" is not stored.** It is calculated when shown: status is `sent` or `partially_paid` **and** `due_date` is before today. A stored "overdue" status would need a daily job and could be wrong if the job fails.
Status changes are automatic where possible: `sent` → `partially_paid` → `paid` by the payment trigger; back to `partially_paid`/`sent` if a payment is reversed.
Edit rule: only `draft` invoices can be edited (D-31). Deleting: only drafts. Voiding: only when the invoice has no `completed` payments (reverse them first — `09-finance.md`).
Indexes: `(organization_id, status)`, `(organization_id, customer_id)`, `(organization_id, issue_date)`, `(organization_id, due_date) where status in ('sent','partially_paid')`, `(organization_id, project_id)`.

#### `invoice_items`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| invoice_id | uuid | ✅ | Composite FK → invoices, on delete cascade (only drafts can be deleted) |
| service_product_id | uuid | | Composite FK → services_products (for reference only) |
| description | text | ✅ | 1–500 chars |
| quantity | numeric(12,3) | ✅ | > 0, up to 3 decimals (e.g. 12.5 sq ft) |
| unit | text | | |
| unit_price | numeric(12,2) | ✅ | ≥ 0 |
| discount_amount | numeric(12,2) | ✅ | Default 0; 0 ≤ discount ≤ line_subtotal (D-11) |
| tax_rate | numeric(5,2) | ✅ | Default 0; 0–100 (D-10) |
| line_subtotal | numeric(12,2) | ✅ | round(quantity × unit_price, 2) — **calculated** |
| line_tax | numeric(12,2) | ✅ | round((line_subtotal − discount_amount) × tax_rate / 100, 2) — **calculated** |
| line_total | numeric(12,2) | ✅ | line_subtotal − discount_amount + line_tax — **calculated** |
| sort_order | integer | ✅ | Order on the invoice |

Rounding: "round half up" to 2 decimals **per line**; invoice totals are sums of the rounded lines, so the printed lines always add up exactly to the total.
Trigger: items can only be added/changed/removed while the invoice is `draft`; after each change the invoice totals are recalculated.
Index: `(organization_id, invoice_id)`, `(organization_id, service_product_id)`.

#### `payments`
Money received from a customer against an invoice.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| invoice_id | uuid | ✅ | Composite FK → invoices. One invoice per payment in V1 (D-14) |
| customer_id | uuid | ✅ | Composite FK → customers. **Copied from the invoice by trigger** (used for client access and reports) |
| amount | numeric(12,2) | ✅ | > 0 and ≤ invoice balance at the time (D-14) |
| payment_date | date | ✅ | Not in the future |
| method | text | ✅ | `cash` · `bank_transfer` · `jazzcash` · `easypaisa` · `cheque` · `card` · `other` (D-15) |
| reference | text | | Cheque number, transaction ID |
| notes | text | | Visible to the linked CLIENT (§1.2) |
| status | text | ✅ | `completed` (default) · `reversed` |
| reversed_at | timestamptz | | |
| reversed_by | uuid | | |
| reversal_reason | text | | Required when reversed |
| created_by | uuid | ✅ | forced |

Payments are created only through the `record_payment()` database function (locks the invoice row, checks balance, inserts, updates invoice) and reversed only through `reverse_payment()`. Never deleted (D-32). Payments cannot be added to `draft` or `void` invoices.
Indexes: `(organization_id, payment_date)`, `(organization_id, invoice_id)`, `(organization_id, customer_id)`.

#### `expense_categories`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| name | text | ✅ | 1–100 chars; `unique (organization_id, lower(name))` |
| archived_at | timestamptz | | |
| created_by | uuid | | forced (empty for the starter categories) |

When an organization is created, a few editable starter categories are added (suggested: Rent, Utilities, Salaries & wages, Transport, Materials, Office supplies, Marketing, Other). The organization can rename or archive them.

#### `expenses`

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| category_id | uuid | ✅ | Composite FK → expense_categories |
| project_id | uuid | | Composite FK → projects (optional: cost of a project) |
| payee | text | | Who was paid |
| description | text | ✅ | 1–500 chars |
| amount | numeric(12,2) | ✅ | > 0. Currency = organization currency |
| expense_date | date | ✅ | |
| method | text | ✅ | Same list as payments |
| reference | text | | |
| status | text | ✅ | `recorded` (default) · `void` |
| voided_at, voided_by, void_reason | | | Reason required when voided |
| created_by | uuid | ✅ | forced |

Receipts are attached through `documents.expense_id` (Step 18).
Indexes: `(organization_id, expense_date)`, `(organization_id, category_id)`, `(organization_id, project_id)`, `(organization_id, status)`.

#### `documents`
Information about uploaded files (the files themselves live in Supabase Storage).

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | |
| bucket | text | ✅ | Storage bucket name (private). Details in `10-documents.md` |
| storage_path | text | ✅ | **Unique.** Always starts with `{organization_id}/` e.g. `{org}/projects/{project_id}/{uuid}-{file}` |
| file_name | text | ✅ | Original name (cleaned) |
| mime_type | text | ✅ | Checked on the server against an allowed list |
| size_bytes | bigint | ✅ | > 0, ≤ limit |
| customer_id | uuid | | Composite FK → customers |
| project_id | uuid | | Composite FK → projects |
| task_id | uuid | | Composite FK → tasks |
| invoice_id | uuid | | Composite FK → invoices |
| expense_id | uuid | | Composite FK → expenses |
| visible_to_client | boolean | ✅ | Default **false** |
| uploaded_by | uuid | ✅ | forced |

Check: **exactly one** of the five link columns is filled (`num_nonnulls(customer_id, project_id, task_id, invoice_id, expense_id) = 1`). Check: expense documents can never be visible to clients (`not (expense_id is not null and visible_to_client)`). Using real columns instead of a generic "entity_type + entity_id" pair lets the database enforce the link and the same-organization rule.
Indexes: `(organization_id, customer_id)`, `(organization_id, project_id)`, `(organization_id, task_id)`, `(organization_id, invoice_id)`, `(organization_id, expense_id)` (each only where not empty).
Delete: real delete of row **and** file (storage counts toward plan limits), logged.

### 4.4 System tables

#### `organization_settings`
Settings the OWNER/ADMIN edit (kept separate from `organizations` so that editing settings can never touch `status`, which only PLATFORM_ADMIN may change). Created automatically together with the organization.

| Column | Type | Req | Notes |
|---|---|---|---|
| organization_id | uuid | ✅ | PK, → organizations, on delete cascade |
| legal_name | text | | Printed on invoices |
| address, city, country | text | | |
| phone, email, website | text | | |
| tax_registration_number | text | | Free text, printed on invoices |
| invoice_prefix | text | ✅ | Default `INV`; 1–10 capital letters/digits (D-13) |
| invoice_due_days | integer | ✅ | Default days until due; 0–365. Starting value 30 (editable) |
| invoice_notes | text | | Default notes for new invoices |
| invoice_terms | text | | Default terms for new invoices |
| tax_label | text | ✅ | Name printed for tax, e.g. "Sales Tax". Default `Tax` (D-10) |
| default_tax_rate | numeric(5,2) | ✅ | Default **0**; 0–100 (D-10) |
| clients_can_see_tasks | boolean | ✅ | Default **false** (D-06) |

#### `number_sequences`
Counters for invoice numbers (and later other document numbers).

| Column | Type | Req | Notes |
|---|---|---|---|
| organization_id | uuid | ✅ | → organizations, on delete cascade |
| sequence_type | text | ✅ | `invoice` (others later) |
| period_year | integer | ✅ | e.g. 2026 (counter restarts each year — D-13) |
| last_value | integer | ✅ | Default 0 |
| updated_at | timestamptz | ✅ | |

PK: `(organization_id, sequence_type, period_year)`.
RLS is on with **no policies**, so nobody can read or change it directly; only the `issue_invoice()` database function uses it.
**How duplicates are prevented:** inside the same transaction that issues the invoice, the function runs one statement: "insert the counter row, or if it exists, add 1 to it, and give me the new value". PostgreSQL locks that counter row until the transaction ends, so if two people issue invoices at the same moment, the second waits a few milliseconds and gets the next number. If issuing fails, the whole transaction is undone including the counter, so there are **no gaps**. The unique constraint on `invoices` is a second safety net. Full explanation in `09-finance.md`.

#### `notifications`
In-app messages for one person.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | uuid | ✅ | PK |
| organization_id | uuid | ✅ | → organizations |
| recipient_user_id | uuid | ✅ | → profiles |
| type | text | ✅ | e.g. `task_assigned`, `project_member_added`, `invoice_issued`, `payment_recorded`, `document_uploaded`, `subscription_expiring` (full list in `11-notifications-audit.md`) |
| title | text | ✅ | |
| body | text | | |
| link_path | text | | Page to open, must start with `/app/` (checked) |
| entity_table | text | | Informational only |
| entity_id | uuid | | Informational only (no FK; the linked page does its own permission check) |
| read_at | timestamptz | | Empty = unread |
| created_at | timestamptz | ✅ | |

Created only by triggers / database functions (never by the browser). The recipient may only set `read_at`.
Index: `(recipient_user_id, read_at, created_at desc)`, `organization_id`.
Retention: D-27.

#### `activity_logs`
The audit trail: who did what, when.

| Column | Type | Req | Notes |
|---|---|---|---|
| id | bigint | ✅ | PK, auto-increasing number |
| organization_id | uuid | | → organizations, on delete cascade. **Empty only for platform-level events** (e.g. plan created) |
| actor_user_id | uuid | | ID of the person (profiles.id). **No foreign key on purpose**, so a log entry can never block a change. Empty = done automatically by the system |
| action | text | ✅ | `insert` / `update` / `delete`, or a named event like `invoice.issued`, `member.role_changed`, `payment.reversed` |
| table_name | text | ✅ | |
| record_id | text | | ID of the changed row (text so it also fits composite keys) |
| changes | jsonb | | For updates **only changed fields** `{"status": {"old": "draft", "new": "sent"}}`; for inserts the new values; for deletes the old values. Sensitive columns (e.g. `token_hash`) are always removed |
| ip_address | inet | | When available |
| user_agent | text | | When available |
| created_at | timestamptz | ✅ | |

Written by a shared audit trigger on every business table (so nothing is missed) plus named events from database functions.
**Append-only:** no update or delete policy exists, and update/delete rights are removed from normal users — nobody (not even OWNER) can edit or delete a log entry through the app.
Indexes: `(organization_id, created_at desc)`, `(organization_id, table_name, record_id)`, `actor_user_id`.
Retention: D-27.

---

## 5. Shared triggers and functions (database side)

| Name | Type | Does |
|---|---|---|
| `set_updated_at()` | trigger | Sets `updated_at = now()` on every update |
| `force_created_by()` | trigger | Sets `created_by` / `uploaded_by` / `author_user_id` = logged-in user on insert |
| `prevent_org_change()` | trigger | Blocks changing `organization_id` |
| `private.current_user_id()` | function | The logged-in person's Clerk id, read from the verified login token (`auth.jwt() ->> 'sub'`) |
| `audit_row_change()` | trigger | Writes `activity_logs` |
| `recalc_invoice_totals()` | trigger on `invoice_items` | Calculates line amounts and invoice totals |
| `apply_payment_to_invoice()` | trigger on `payments` | Updates `amount_paid` and invoice status |
| `create_organization(name, slug, currency, timezone)` | function | Creates organization + settings + OWNER membership + starter expense categories in one transaction |
| `accept_invitation(token)` | function | Checks token/expiry/email, creates membership, marks invite accepted |
| `transfer_ownership(org, new_owner_membership)` | function | Swaps OWNER role in one transaction |
| `issue_invoice(invoice_id)` | function | Gives number, snapshots `bill_to`, sets status `sent` |
| `record_payment(...)` / `reverse_payment(...)` | functions | Safe payment changes |
| Helper functions for RLS | functions | `is_member`, `has_role`, `is_platform_admin`, `client_customer_id`, `can_write` — see `06-authorization-rls.md` |

The complete list of database functions (including `void_invoice`, `duplicate_invoice`, `void_expense`, platform functions) is in `06-authorization-rls.md` §3–4.

---

## 6. Performance notes

- Every list page is **paginated** (e.g. 25 rows per page) and filtered by `organization_id` first; the indexes above start with `organization_id` for that reason.
- Dashboard numbers (totals, counts) are calculated **in the database** with `sum`/`count` queries or database functions, never by loading whole tables into the website.
- Search in V1 uses simple "contains" matching on names; if lists grow large, a trigram index (a special index for fast text search) can be added later with a migration.

---

## 7. Which build step creates which table

| Build step (`docs/BUILD_ORDER.md`) | Tables |
|---|---|
| Step 8 — Database foundation | `organizations`, `organization_settings`, `profiles`, `memberships` (without `customer_id` FK), `invitations` (without `customer_id` FK), `platform_admins`, `activity_logs` |
| Step 12 — Customers | `customers`; adds the `customer_id` composite FKs on `memberships` and `invitations` |
| Step 13 — Projects & tasks | `projects`, `project_members`, `tasks`, `task_comments` |
| Step 14 — Services/products | `services_products` |
| Step 15 — Invoices | `invoices`, `invoice_items`, `number_sequences` |
| Step 16 — Payments | `payments` |
| Step 17 — Expenses | `expense_categories` (with starter categories for every existing organization), `expenses` |
| Step 18 — Documents | `documents` + storage buckets and policies |
| Step 19 — Notifications | `notifications` |
| Step 22 — Platform & billing | `plans`, `subscriptions`, `subscription_payments`, `platform_settings`, `platform_announcements` (existing organizations get a trial subscription row in the same migration) |

---

## 8. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-10 | Tax model | Optional **tax % per invoice line** (default 0), organization sets a default rate and a tax label. **No tax rule is built in.** | Works for "no tax", one flat tax, or items with different rates, without the software assuming any law. |
| D-11 | Discount model | **Discount as an amount per invoice line** (default 0), tax calculated after discount. | Simple, exact math; a whole-invoice discount spread over lines with different tax rates is confusing. |
| D-12 | Currency | **One currency per organization** (default PKR), chosen at onboarding, locked after the first issued invoice. Multi-currency later. | Mixed currencies make totals and reports wrong unless exchange rates are handled. |
| D-13 | Invoice number format | `{PREFIX}-{YYYY}-{NNNN}` e.g. `INV-2026-0001`; prefix editable; counter **restarts every calendar year**; number given **when the invoice is issued**, not when the draft is created. | Matches the brief's example; issuing-time numbers mean deleted drafts never leave gaps. |
| D-14 | Payment rules | Each payment belongs to **one invoice**; **no overpayment** (amount ≤ balance); **no advance / unallocated payments** in V1. | Keeps balances always correct and easy to understand; advances and credit notes come in V2. |
| D-15 | Payment methods | **Fixed list**: cash, bank transfer, JazzCash, Easypaisa, cheque, card, other (+ free "reference" field). | Covers Pakistan's common methods without an extra settings screen; can become configurable later. |
| D-16 | Separate `customer_contacts` table? | **No in V1**; one contact person on the customer. | Most small businesses have one contact per customer. |
| D-17 | Projects without a customer / tasks without a project? | **Both allowed** (internal projects, general tasks). | Businesses also have internal work (e.g. "renovate showroom"). |
| D-18 | Project budget field? | **Not in V1.** V2: in a separate table only finance roles can read. | A budget column in `projects` would be readable by clients (RLS is per row, not per column). |
| D-19 | Stock / inventory tracking for products? | **No in V1.** | Stock control is a big module of its own (purchases, adjustments, valuation). |
| D-23 | Invitation expiry | **7 days**, resend creates a fresh link. | Long enough for busy people, short enough to be safe. |
| D-27 | How long to keep activity logs and notifications | **Keep logs forever** in V1; **delete read notifications after 90 days**. | Logs are small and useful for disputes; old notifications only clutter. |
| D-28 | Can the organization slug (URL name) be changed? | **Only by PLATFORM_ADMIN** on request in V1. | Changing it breaks bookmarked links and printed links; rare need. |
| D-31 | Can a sent (issued) invoice be edited? | **No.** Void it (with reason) and use "Duplicate as new draft". | Keeps a trustworthy record: what the customer received never silently changes. |
| D-32 | Can a payment be deleted? | **No — only reversed** (with reason); the reversal is logged and the invoice balance goes back up. | Money history must stay complete for trust and for the accountant. |
