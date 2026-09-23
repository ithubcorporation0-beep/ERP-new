# 07 — Panels

> A **panel** is what one role sees after login: its menu, dashboard and pages.
> All organization panels share **one set of routes** under `/app/[orgSlug]/…`. What each person sees on a page depends on their role: the menu shows only allowed items, the server checks the role, and RLS returns only allowed rows. Example: `/app/wajid-marble/tasks` shows **all** tasks to a MANAGER and **only my tasks** to an EMPLOYEE.
> This avoids building six copies of every page, and there is still one place where each rule is checked.

---

## 1. Shared rules for every list page

| Topic | Rule |
|---|---|
| Pagination | 25 rows per page, done in the database (`range`/`limit`), page number in the URL (`?page=2`) |
| Search | One search box (`?q=`), "contains" match on the main text fields listed per module, done in the database |
| Filters | In the URL (`?status=active&customer=…`) so a filtered list can be bookmarked or shared |
| Sorting | Default per module; clickable column headers for the main columns |
| Archived records | Hidden by default; "Show archived" filter (`?archived=1`) for roles that can archive |
| Empty state | Friendly text + main action button (e.g. "No customers yet — Add customer") |
| Detail pages | Unknown or forbidden ID → **404 Not found** (never reveal that it exists) |
| Forms | Same form for create and edit; validated in browser (for comfort) and on the server with Zod (for security) |
| Money | Shown in the organization currency with 2 decimals (e.g. `Rs 12,500.00`) |
| Dates | Shown in the organization timezone, format `23 Sep 2026` |

## 2. Route map

### 2.1 Organization routes (`/app/[orgSlug]/…`)

| Route | Module | Roles that can open it |
|---|---|---|
| `/` | Dashboard (content depends on role) | all |
| `/team`, `/team/[membershipId]` | Members + invitations, member detail | OWNER, ADMIN, MANAGER (view) |
| `/customers`, `/customers/new`, `/customers/[id]`, `/customers/[id]/edit` | Customers | OWNER, ADMIN, MANAGER, ACCOUNTANT (edit rules per matrix) |
| `/projects`, `/projects/new`, `/projects/[id]`, `/projects/[id]/edit` | Projects | OWNER, ADMIN, MANAGER, ACCOUNTANT (view), EMPLOYEE (mine), CLIENT (mine) |
| `/tasks`, `/tasks/new`, `/tasks/[id]`, `/tasks/[id]/edit` | Tasks | OWNER, ADMIN, MANAGER, ACCOUNTANT (view), EMPLOYEE (mine), CLIENT (only if D-06 on) |
| `/services` , `/services/new`, `/services/[id]/edit` | Services/products | OWNER, ADMIN, ACCOUNTANT, MANAGER (view) |
| `/invoices`, `/invoices/new`, `/invoices/[id]`, `/invoices/[id]/edit`, `/invoices/[id]/print` | Invoices | OWNER, ADMIN, ACCOUNTANT, MANAGER (view, D-02), CLIENT (mine) |
| `/payments`, `/payments/[id]` | Payments | OWNER, ADMIN, ACCOUNTANT, MANAGER (view), CLIENT (mine) |
| `/expenses`, `/expenses/new`, `/expenses/[id]`, `/expenses/[id]/edit`, `/expenses/categories` | Expenses | OWNER, ADMIN, ACCOUNTANT |
| `/documents` | All documents I can see | all (filtered) |
| `/reports`, `/reports/[report]` | Reports | OWNER, ADMIN, MANAGER (work), ACCOUNTANT (financial) |
| `/notifications` | Notification center | all |
| `/activity` | Activity log | OWNER, ADMIN |
| `/settings`, `/settings/invoices` | Organization & invoice settings | OWNER, ADMIN |
| `/billing` | Plan, usage, subscription history | OWNER (ADMIN: plan name only, on `/settings`) |
| `/profile` | My profile | all |

### 2.2 Platform routes (`/platform/…`)

`/platform` (dashboard), `/platform/organizations`, `/platform/organizations/[id]`, `/platform/plans`, `/platform/subscriptions`, `/platform/users`, `/platform/announcements`, `/platform/settings`, `/platform/audit-log`, `/platform/profile`.

## 3. Menus per role

| Menu item | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|
| Dashboard | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Customers | ✅ | ✅ | ✅ | ✅ | — | — |
| Projects | ✅ | ✅ | ✅ | ✅ | "My Projects" | "My Projects" |
| Tasks | ✅ | ✅ | ✅ | ✅ | "My Tasks" | "My Tasks" (if D-06 on) |
| Team | ✅ | ✅ | ✅ | — | — | — |
| Services/Products | ✅ | ✅ | ✅ | ✅ | — | — |
| Invoices | ✅ | ✅ | ✅ (D-02) | ✅ | — | "My Invoices" |
| Payments | ✅ | ✅ | ✅ (D-02) | ✅ | — | "My Payments" |
| Expenses | ✅ | ✅ | — | ✅ | — | — |
| Documents | ✅ | ✅ | ✅ | ✅ | "My Documents" | "My Documents" |
| Reports | ✅ | ✅ | ✅ (work) | ✅ (financial) | — | — |
| Activity Log | ✅ | ✅ | — | — | — | — |
| Settings | ✅ | ✅ | — | — | — | — |
| Billing | ✅ | — | — | — | — | — |
| Notifications (bell) / Profile (user menu) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 4. Platform Admin panel (`/platform`)

| Module | Purpose | Pages & actions | Search / filters | Tables | Rules |
|---|---|---|---|---|---|
| Dashboard | Health of the SaaS | Counts: organizations by status, trials ending in 7 days, subscriptions ending in 7 days, new signups this month | — | organizations, subscriptions | Counts only; no tenant business data (D-01) |
| Organizations | Manage tenants | List; detail (name, slug, status, owner name/email, members count, customers count, storage used, plan, subscription dates); **Suspend** (reason required) / **Activate**; change slug on request (D-28); mark for permanent deletion after 30 days (D-24) | Search name/slug/owner email; filter status, plan | organizations, memberships (counts), subscriptions, documents (sum of sizes) | Every action logged; suspending takes effect immediately |
| Plans | Price list of the SaaS | List, create, edit, deactivate | — | plans | Deactivated plans stay on existing subscriptions |
| Subscriptions | Manual billing | List; **Record payment & activate/extend** (plan, amount, method, reference, paid on, period) ; change plan; mark expired/cancelled; notes | Filter status, plan, "ending within N days" | subscriptions, subscription_payments | Numbers & behaviour in `12-billing-subscriptions.md` |
| Platform users | Accounts | List of all accounts (name, email, created, status, number of memberships); **Disable / Enable account** (reason) | Search name/email; filter status | profiles, memberships (counts) | Uses admin client #1; cannot disable yourself |
| Announcements | Messages to businesses | List, create, edit, publish/unpublish, start/end time, level | Filter published | platform_announcements | Plain text only |
| Platform settings | Global switches | `signups_enabled`, `default_trial_days`, `support_contact`, `max_owned_organizations` (D-37) | — | platform_settings | |
| Platform audit log | What platform admins did | List, filter by action/admin/date | Filter action, actor, date range | activity_logs (organization_id null + platform actions) | Read-only |

---

## 5. Owner / Admin panel

OWNER and ADMIN see the same panel; differences: **Billing** and the **danger zone** (transfer ownership, delete organization) are OWNER-only, and ADMIN cannot change the OWNER's membership.

### 5.1 Dashboard
- Cards: received this month, invoiced this month, unpaid total (balance of sent/partially paid invoices), overdue invoices (count + amount), expenses this month, active projects, overdue tasks.
- Lists: 5 latest payments, 5 overdue invoices, 5 tasks due soon.
- Getting-started checklist until done (logo, invite team, first customer, first invoice).
- Announcement banner (platform), subscription/trial banner (OWNER).
- All numbers calculated in the database (Step 20).

### 5.2 Users & Invitations (`/team`)
| Item | Details |
|---|---|
| Purpose | Manage who can access the organization |
| Pages | Tabs: **Members** (name, email, role, status, joined) · **Invitations** (email, role, customer, status, expires, invited by) |
| CRUD | Invite; resend; cancel; change role; disable/enable; transfer ownership (OWNER); (members cannot be deleted) |
| Search / filters | Search name/email; filter role, status |
| Pagination | 25 |
| Permissions | OWNER, ADMIN (manage); MANAGER (view Members only) |
| Tables | memberships, profiles, invitations, customers |
| Business rules | No self role change; ADMIN cannot touch OWNER; invite role cannot be OWNER; CLIENT invite needs a customer; plan user limit; invite expires in 7 days (D-23) |

### 5.3 Customers
| Item | Details |
|---|---|
| Purpose | Keep the customer list |
| Pages | List; new; detail with tabs: **Overview** (contact info), **Projects**, **Invoices**, **Payments**, **Documents**, **Client logins** (who is linked; "Invite client login" button); edit |
| CRUD | Create, edit, archive/restore (no delete) |
| Search | name, contact person, phone, email, city |
| Filters | archived; has unpaid balance |
| Sort | name (default), created date |
| Permissions | per matrix §3.4 |
| Tables | customers, projects, invoices, payments, documents, memberships, invitations |
| Business rules | Customer with open invoices can still be archived but a warning is shown; archived customers cannot get new projects/invoices |

### 5.4 Employees / Team
The **Members** tab of `/team` is the team list. Member detail (`/team/[membershipId]`): role, job title, status, projects they are on, open tasks assigned — so managers can see workload.

### 5.5 Projects
| Item | Details |
|---|---|
| Purpose | Track work done for a customer (or internal) |
| Pages | List; new; detail with tabs: **Overview**, **Tasks**, **Members**, **Invoices** (finance roles), **Documents**; edit |
| CRUD | Create, edit, change status, archive/restore; add/remove members |
| Search | name, customer name |
| Filters | status, customer, due date range, "overdue" (due date passed and not completed) |
| Sort | due date (default), name, created |
| Permissions | per matrix §3.5 |
| Tables | projects, project_members, tasks, customers, invoices, documents |
| Business rules | Customer must be active (not archived); completing a project does not auto-complete tasks (warning shown if tasks are still open) |

### 5.6 Tasks
| Item | Details |
|---|---|
| Purpose | Track individual pieces of work |
| Pages | List (table + optional board by status); new; detail with **comments** and **documents**; edit |
| CRUD | Create, edit, assign, change status, archive/restore; comments add/edit/delete |
| Search | title |
| Filters | status, priority, assignee, project, due date range, overdue, "unassigned" |
| Sort | due date (default), priority, created |
| Permissions | per matrix §3.5 |
| Tables | tasks, task_comments, projects, memberships, profiles, documents |
| Business rules | Assignee must be an active non-client member; assigning adds the person to the project members; status `done` sets `completed_at` |

### 5.7 Services / Products
| Item | Details |
|---|---|
| Purpose | Price list for quick invoicing |
| Pages | List; new; edit |
| CRUD | Create, edit, archive/restore |
| Search | name, SKU |
| Filters | type (service/product), archived |
| Permissions | OWNER, ADMIN, ACCOUNTANT edit; MANAGER view |
| Tables | services_products |
| Business rules | SKU unique per organization; price ≥ 0; editing prices never changes existing invoices |

### 5.8 Invoices
| Item | Details |
|---|---|
| Purpose | Bill customers |
| Pages | List; new (draft editor with lines); detail (status, lines, totals, payments, documents, history); edit (drafts only); print view |
| CRUD | Create draft, edit draft, delete draft, **Issue**, **Void** (reason), **Duplicate as new draft**, record payment (from detail) |
| Search | invoice number, customer name |
| Filters | status (incl. computed "overdue"), customer, project, issue date range, due date range |
| Sort | issue date (default, newest first), due date, total, balance |
| Permissions | per matrix §3.7 |
| Tables | invoices, invoice_items, services_products, customers, projects, payments, organization_settings, number_sequences |
| Business rules | All in `09-finance.md` |

### 5.9 Payments
| Item | Details |
|---|---|
| Purpose | Record money received |
| Pages | List; detail (with printable receipt view); "Record payment" dialog from an invoice |
| CRUD | Record, reverse (reason). No edit, no delete |
| Search | reference, invoice number, customer name |
| Filters | method, date range, customer, status (completed/reversed) |
| Sort | payment date (default, newest first) |
| Permissions | per matrix §3.7 |
| Tables | payments, invoices, customers |
| Business rules | `09-finance.md` |

### 5.10 Expenses
| Item | Details |
|---|---|
| Purpose | Record money spent |
| Pages | List; new; detail (with receipt documents); edit; categories page |
| CRUD | Create, edit, void (reason); categories create/rename/archive |
| Search | description, payee, reference |
| Filters | category, project, date range, method, status |
| Sort | expense date (default) |
| Permissions | OWNER, ADMIN, ACCOUNTANT |
| Tables | expenses, expense_categories, projects, documents |
| Business rules | `09-finance.md` |

### 5.11 Documents
| Item | Details |
|---|---|
| Purpose | One place to find all files I can see (files are uploaded from the record they belong to) |
| Pages | List with download buttons |
| CRUD | Download, rename, toggle "visible to client", delete (per matrix); upload happens on customer/project/task/invoice/expense pages |
| Search | file name |
| Filters | attached to (customer/project/task/invoice/expense), file type, uploaded by, date, visible to client |
| Tables | documents (+ linked tables for names) |
| Business rules | `10-documents.md` |

### 5.12 Reports
Report list (details and formulas in `09-finance.md` §9 and Step 20):
- **Work** (OWNER, ADMIN, MANAGER; ACCOUNTANT view): projects by status, tasks by status/assignee, overdue tasks, workload per member.
- **Financial** (OWNER, ADMIN, ACCOUNTANT): sales (invoiced) by month, money received by month and by method, receivables/aging (unpaid invoices by age: 0–30, 31–60, 61–90, 90+ days), customer statements, expenses by category/month, income vs expenses summary (D-41).
- All filters: date range (default this month), customer, project where it makes sense.

### 5.13 Notifications
Bell icon with unread count in the header; dropdown with the latest 10; `/notifications` page with all (25 per page), filter unread; "mark as read", "mark all as read". Clicking opens the linked page (which does its own permission check).

### 5.14 Activity Log
| Item | Details |
|---|---|
| Purpose | See who changed what |
| Pages | List (time, person, action, record, changed fields); detail drawer with old → new values |
| Filters | date range, person, table/module, action |
| Pagination | 50 |
| Permissions | OWNER, ADMIN (read-only) |
| Tables | activity_logs, profiles |

### 5.15 Settings
- **Organization** (`/settings`): name, logo, legal name, address, phone, email, website, tax registration number, timezone, currency (OWNER, only before first issued invoice), "Clients can see tasks" (D-06), current plan, limits and usage (ADMIN, read-only).
- **Invoices** (`/settings/invoices`): prefix, default due days, default notes/terms, tax label, default tax rate (D-10).
- **Danger zone** (OWNER): transfer ownership, request organization deletion (D-24).

### 5.16 Billing (OWNER only)
Current plan, status, trial/period end date, usage vs limits (users, clients, customers, storage), subscription payment history, "How to pay / request plan change" instructions (manual billing, `12-billing-subscriptions.md`).

---

## 6. Manager panel

Same pages as Owner/Admin, limited to:
- **Dashboard**: active projects, tasks by status, overdue tasks, tasks per employee, projects due in 14 days, invoices waiting for payment on my customers (view, D-02).
- **Customers, Projects, Tasks**: full work access (create/edit/archive, assign).
- **Team**: view members + workload.
- **Services/Products**: view.
- **Invoices, Payments**: view only (D-02) — no create/record buttons.
- **Documents**: all except expense documents.
- **Reports**: work reports only.
- No Expenses, Activity Log, Settings, Billing.

## 7. Accountant panel

- **Dashboard**: received this month, invoiced this month, unpaid total, overdue invoices, expenses this month, top 5 customers by balance.
- **Customers**: view, create, edit (D-08), no archive.
- **Projects, Tasks**: view only (D-03), no comments.
- **Services/Products, Invoices, Payments, Expenses (+ categories)**: full finance access.
- **Documents**: customer/invoice/expense documents (upload + manage own); project/task documents view.
- **Reports**: financial (+ work reports view).
- No Team, Activity Log, Settings, Billing.

## 8. Employee panel

| Module | Details |
|---|---|
| Dashboard | My tasks: overdue, due today, due this week; my projects; recent notifications |
| My Profile | `/profile` |
| My Tasks (`/tasks`) | Only tasks assigned to me. Filters: status, project, due date. Actions: change status, add/edit/delete own comments, upload documents (D-22). Cannot create, reassign or edit title/dates (D-07) |
| My Projects (`/projects`) | Only projects I'm a member of. Shows project info, basic customer info (D-05), my tasks in it, documents. No invoices tab |
| My Documents (`/documents`) | Documents of my tasks and my projects |
| Notifications | Task assigned, comment on my task, added to project |

## 9. Client panel

### 9.1 How a client is limited to their own customer

1. OWNER/ADMIN opens a customer → **Client logins** → "Invite client login" → invitation with role CLIENT and `customer_id` = that customer.
2. When accepted, the `memberships` row has `role = 'client'` and `customer_id` = that customer. A database check makes `customer_id` **required** for clients and **forbidden** for other roles; a composite foreign key makes sure the customer belongs to the **same organization**.
3. The database function `private.client_customer_id(org)` returns this `customer_id` for the logged-in user — read from the database, never from the URL or the browser.
4. Every client RLS policy compares the row's customer with this value: `customers.id`, `projects.customer_id`, `invoices.customer_id` (and not draft), `payments.customer_id`, documents linked to those records **and** `visible_to_client = true`, tasks of their projects only if the organization turned on D-06.
5. Changing the link (moving a client login to a different customer) is not possible in V1: disable the membership and send a new invitation (keeps history clean).

### 9.2 Client pages

| Module | Details |
|---|---|
| Dashboard | My active projects, total balance due, overdue invoices, last 5 invoices, last 5 payments |
| My Profile | `/profile` |
| My Projects | My customer's projects: name, status, dates, description; tasks tab only if D-06 on; documents marked visible |
| My Tasks | Only if D-06 on: title, status, due date (no comments, no assignee names) |
| My Invoices | Issued invoices (sent, partially paid, paid, void — D-42); print view; filter status, date |
| My Payments | Payments on my invoices (reversed ones shown as "reversed") |
| My Documents | Documents marked visible to client on my records; download only (D-21: no upload) |
| Notifications | Invoice issued, payment recorded/reversed, document shared, project status changed |

Clients never see: other customers, team lists, prices list, expenses, drafts, internal comments, reports, settings, activity log.

## 10. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-42 | Do clients see void invoices? | **Yes**, clearly stamped "VOID". | The customer may already have received it; hiding it causes confusion. |

Referenced: D-01, D-02, D-03, D-05, D-06, D-07, D-08, D-10, D-21, D-22, D-23, D-24, D-28, D-37, D-41.
