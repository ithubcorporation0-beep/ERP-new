# 02 — Roles & Permissions

> A **role** is a label that decides what a person may see and do.
> A **permission** is one specific thing a role may do (example: "create invoice").

---

## 1. Two levels of roles

| Level | Role | Where it is stored | Scope |
|---|---|---|---|
| Platform | `PLATFORM_ADMIN` | `platform_admins` table | The whole SaaS (all organizations' *management* info, not their business data — D-01) |
| Organization | `OWNER`, `ADMIN`, `MANAGER`, `ACCOUNTANT`, `EMPLOYEE`, `CLIENT` | `memberships.role` | One organization only |

Rules:

- A role is **only** read from the database tables above. It is **never** read from `user_metadata` (information users can edit about themselves), because a user could simply write "OWNER" there.
- One person can have **different roles in different organizations** (one membership per organization).
- One person can have **only one role inside the same organization** (unique membership per user + organization).
- A `PLATFORM_ADMIN` can also be a normal member of an organization (example: the platform owner's own business). In that organization they have only the rights of their membership role.
- Each organization has **exactly one OWNER**. Ownership can be transferred, but never removed.

### Fixed roles (V1) vs custom roles (future)

**Decision: fixed roles in V1.** The 7 roles above are built into the code and database rules.
Why: fixed roles can be tested completely (every role × every page), security rules stay simple, and small businesses rarely need more. **Custom roles** (an organization designs its own role with chosen permissions) are a future feature; the database is designed so that roles can later move into a `roles` + `role_permissions` table without changing business tables.

---

## 2. Role by role

Legend for "Data": **V** = view, **C** = create, **U** = update, **D** = delete/archive/void.

### 2.1 PLATFORM_ADMIN (the software owner)

| Item | Access |
|---|---|
| Purpose | Runs the SaaS: organizations, plans, subscriptions, announcements, platform settings. |
| Dashboard | `/platform` — number of organizations (active / trial / suspended), trials ending soon, subscriptions expiring, new signups. |
| Pages | Organizations, Organization detail (status, plan, owner name/email, member count, storage used), Plans, Subscriptions (manual activation/extension), Platform users (accounts: enable/disable), Announcements, Platform settings, Platform audit log. |
| Data | V/U organizations' **management** info (name, slug, status, plan, counts). C/U/D plans, announcements, platform settings. U subscriptions (manual activation). U user account status (disable/enable a whole account). |
| Tenant business data (customers, invoices, files…) | **None by default.** D-01. |
| Financial access | Only platform billing (subscription payments recorded manually). |
| User management | Can disable/enable any user account on the platform. Cannot change roles inside an organization. |
| Reporting | Platform-level counts only (never totals of a tenant's invoices). |
| Settings | Platform settings. |
| Billing | Manages all organizations' subscriptions (manual billing). |
| Who can become PLATFORM_ADMIN | Only by a SQL command run by me in the Supabase dashboard (no button in the app). Safer: nobody can promote themselves through the website. |

### 2.2 OWNER

| Item | Access |
|---|---|
| Purpose | The person who created the organization. Full control, including subscription and deleting the organization. |
| Dashboard | Business overview: money received this month, unpaid invoices total, overdue invoices, expenses this month, active projects, overdue tasks, team activity. |
| Pages | Everything in the Owner/Admin panel, plus **Billing** and the danger zone (transfer ownership, delete organization). |
| Data | V/C/U/D all organization data (within the business rules — e.g. issued invoices are voided, not deleted; payments reversed, not deleted). |
| Financial access | Full. |
| User management | Invite any role except OWNER; change any member's role (not their own); disable members; transfer ownership to another active member. |
| Reporting | All reports. |
| Settings | All organization settings (name, logo, address, invoice settings, tax settings, currency before the first invoice). |
| Billing | View plan and usage, request plan change, see subscription history. |

### 2.3 ADMIN

| Item | Access |
|---|---|
| Purpose | Runs the organization day to day. Same as OWNER **except**: billing, deleting the organization, transferring ownership, touching the OWNER's membership. |
| Dashboard | Same as OWNER. |
| Pages | Owner/Admin panel without Billing and without the danger zone. |
| Data | Same as OWNER. |
| Financial access | Full. |
| User management | Invite any role except OWNER; change role / disable any member except the OWNER and except themselves. |
| Reporting | All reports. |
| Settings | All organization settings except billing. |
| Billing | No (can see the plan name, limits and usage on Settings — needed when inviting people — but not payments). |

### 2.4 MANAGER

| Item | Access |
|---|---|
| Purpose | Manages customers, projects, tasks and the team's work. |
| Dashboard | Active projects, tasks by status, overdue tasks, tasks per employee, projects due soon. |
| Pages | Dashboard, Customers, Team (read-only list), Projects, Tasks, Services/Products (view), Invoices & Payments (view — D-02), Documents, Reports (work reports), Notifications, My Profile. |
| Data | V/C/U/archive customers, projects, tasks, task comments, project members. V services/products. |
| Financial access | **D-02.** Recommended: **view** invoices and payments only (to answer "has this customer paid?"); no creating/editing invoices or payments, no expenses, no financial reports. |
| User management | View team members (needed to assign work). Cannot invite (D-09) or change roles. |
| Reporting | Work reports (projects, tasks, workload). |
| Settings | None (own profile only). |
| Billing | No. |

### 2.5 ACCOUNTANT

| Item | Access |
|---|---|
| Purpose | Manages invoices, payments, expenses and financial reports. |
| Dashboard | Money received this month, unpaid and overdue invoices, expenses this month, top customers by balance. |
| Pages | Dashboard, Customers, Projects & Tasks (view — D-03), Services/Products, Invoices, Payments, Expenses, Expense categories, Documents (finance-related), Reports (financial), Notifications, My Profile. |
| Data | V/C/U/D invoices (drafts deleted, issued ones voided), invoice items, payments (record / reverse), expenses, expense categories, services/products. V customers; C/U customers — D-08 (recommended: yes). |
| Projects/tasks | **D-03.** Recommended: **view only** (to know what to invoice); no creating or changing. |
| Financial access | Full (except billing of the SaaS subscription). |
| User management | None. |
| Reporting | Financial reports (revenue, receivables, expenses, profit & loss summary). |
| Settings | Expense categories only. Invoice & tax settings stay with OWNER/ADMIN. |
| Billing | No. |

### 2.6 EMPLOYEE

| Item | Access |
|---|---|
| Purpose | Works on the tasks and projects assigned to them. |
| Dashboard | My tasks due today / this week / overdue, my projects. |
| Pages | Dashboard, My Tasks, My Projects, My Documents, Notifications, My Profile. |
| Data | V tasks **assigned to them**; U status of those tasks; C/U/D own comments on those tasks. V projects **they are a member of** (via `project_members`). V basic customer info (name, phone, address) of those projects — D-05. Upload documents to their tasks/projects — D-22. |
| Create tasks | **D-07.** Recommended: **no** (managers plan work; keeps "my tasks" clean). |
| Financial access | None. No prices, invoices, payments or expenses. |
| User management | None. Sees names of people on the same projects only. |
| Reporting | None (own dashboard only). |
| Settings | Own profile only. |
| Billing | No. |

### 2.7 CLIENT

| Item | Access |
|---|---|
| Purpose | An external customer of the organization who logs in to check their own work and money. |
| Link | Every CLIENT membership is linked to exactly **one** customer record of that organization (`memberships.customer_id`). D-29. |
| Dashboard | My active projects, my unpaid balance, recent invoices, recent payments. |
| Pages | Dashboard, My Profile, My Projects, My Tasks (only if allowed — D-06), My Invoices, My Payments, My Documents, Notifications. |
| Data | V **only records of their own customer**: projects, invoices (issued ones — never drafts), payments (not reversed ones' internal notes), documents marked "visible to client". |
| Tasks | **D-06.** Recommended: an organization setting "Clients can see tasks", **off by default**. When on, clients see task title, status and due date on their projects — never comments or who is assigned. |
| Upload files | **D-21.** Recommended: **no** in V1. |
| Financial access | Own invoices and payments only. |
| User management / Reporting / Settings / Billing | None (own profile only). |

---

## 3. Permission matrix

Legend:
**✅** = yes (whole organization) · **👁** = view only · **Own** = only their own record · **Assigned** = only items assigned to them / projects they are a member of · **Linked** = only records of their linked customer · **❌** = no · **D-xx** = open decision (the recommended default is shown after it).

Platform Admin column: the platform admin has **no rights inside an organization** unless they are also a member of it. ❌ in that column means "not through the platform role".

### 3.1 Platform

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View list of all organizations | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Suspend / activate an organization | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Manage plans | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Activate / extend a subscription (manual billing) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Publish platform announcements | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Read platform announcements | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | D-30 → ❌ |
| Disable / enable any user account | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Platform settings | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Platform audit log | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Read an organization's business data | D-01 → ❌ | — | — | — | — | — | — |

### 3.2 Organization, subscription, settings

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| See organization name & logo | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Edit organization profile (name, logo, address, contact) | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Edit invoice & tax settings | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Change organization currency (only before first invoice) | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Change "clients can see tasks" setting (D-06) | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| View plan, limits & usage | ✅ | ✅ | 👁 | ❌ | ❌ | ❌ | ❌ |
| Request plan change / see subscription history | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Transfer ownership | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Delete organization (D-24) | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 3.3 Users, memberships, invitations

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View team member list | ❌ | ✅ | ✅ | 👁 | ❌ (sees names on tasks only) | ❌ (co-members on own projects only) | ❌ |
| Invite ADMIN | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Invite MANAGER / ACCOUNTANT / EMPLOYEE | ❌ | ✅ | ✅ | D-09 → ❌ | ❌ | ❌ | ❌ |
| Invite CLIENT (linked to a customer) | ❌ | ✅ | ✅ | D-09 → ❌ | ❌ | ❌ | ❌ |
| Resend / cancel invitation | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Change a member's role | ❌ | ✅ (not own) | ✅ (not Owner, not own) | ❌ | ❌ | ❌ | ❌ |
| Disable / re-enable a member | ❌ | ✅ (not own) | ✅ (not Owner, not own) | ❌ | ❌ | ❌ | ❌ |
| Change own role | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Edit own profile (name, phone, photo, password) | Own | Own | Own | Own | Own | Own | Own |
| Leave an organization | — | ❌ (transfer first) | ✅ | ✅ | ✅ | ✅ | ❌ (ask the business) |

### 3.4 Customers

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View customers | ❌ | ✅ | ✅ | ✅ | ✅ | D-05 → 👁 basic info, Assigned | Linked (own record) |
| Create / edit customers | ❌ | ✅ | ✅ | ✅ | D-08 → ✅ | ❌ | ❌ |
| Archive / restore customers | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |

### 3.5 Projects & tasks

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View projects | ❌ | ✅ | ✅ | ✅ | D-03 → 👁 | Assigned | Linked |
| Create / edit / archive projects | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Add / remove project members | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| View tasks | ❌ | ✅ | ✅ | ✅ | D-03 → 👁 | Assigned | D-06 → ❌ (off by default) |
| Create / edit / archive tasks, assign people | ❌ | ✅ | ✅ | ✅ | ❌ | D-07 → ❌ | ❌ |
| Change task status | ❌ | ✅ | ✅ | ✅ | ❌ | Assigned | ❌ |
| View task comments | ❌ | ✅ | ✅ | ✅ | D-03 → 👁 | Assigned | ❌ |
| Add comments | ❌ | ✅ | ✅ | ✅ | ❌ | Assigned | ❌ |
| Edit / delete a comment | ❌ | Own + delete any | Own + delete any | Own | ❌ | Own | ❌ |

### 3.6 Services / products

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View services/products & prices | ❌ | ✅ | ✅ | 👁 | ✅ | ❌ | ❌ |
| Create / edit / archive | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |

### 3.7 Invoices & payments

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View invoices | ❌ | ✅ | ✅ | D-02 → 👁 | ✅ | ❌ | Linked (issued only, never drafts) |
| Create / edit **draft** invoices | ❌ | ✅ | ✅ | D-02 → ❌ | ✅ | ❌ | ❌ |
| Delete a **draft** invoice | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Issue (send) an invoice — gives it a number | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Void an issued invoice (with reason) | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Print / view invoice page | ❌ | ✅ | ✅ | D-02 → ✅ | ✅ | ❌ | Linked |
| View payments | ❌ | ✅ | ✅ | D-02 → 👁 | ✅ | ❌ | Linked |
| Record a payment | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Reverse a payment (with reason) | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Delete a payment | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 3.8 Expenses

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View expenses | ❌ | ✅ | ✅ | D-02 → ❌ | ✅ | ❌ | ❌ |
| Record / edit expenses | ❌ | ✅ | ✅ | ❌ | ✅ | D-20 → ❌ | ❌ |
| Void an expense (with reason) | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Manage expense categories | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |

### 3.9 Documents (files)

A person can see a document only if they can see the record it is attached to (customer, project, task, invoice, expense). Clients additionally need the "visible to client" flag.

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| View / download documents | ❌ | ✅ | ✅ | ✅ (not on expenses) | ✅ (customers, invoices, expenses; projects/tasks 👁 per D-03) | Assigned | Linked + "visible to client" only |
| Upload documents | ❌ | ✅ | ✅ | ✅ customers/projects/tasks | ✅ customers/invoices/expenses | D-22 → Assigned | D-21 → ❌ |
| Mark document visible to client | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Delete documents | ❌ | ✅ | ✅ | Own uploads | Own uploads (not on issued invoices / expenses) | Own uploads | ❌ |
| Upload organization logo | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 3.10 Reports, dashboards, notifications, activity log

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|
| Own dashboard | ✅ (platform) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Work reports (projects, tasks, workload) | ❌ | ✅ | ✅ | ✅ | D-03 → 👁 | ❌ | ❌ |
| Financial reports (revenue, receivables, expenses, P&L summary) | ❌ | ✅ | ✅ | D-02 → ❌ | ✅ | ❌ | ❌ |
| Own statement (my invoices, payments, balance) | ❌ | — | — | — | — | — | Linked |
| Read own notifications / mark read | Own | Own | Own | Own | Own | Own | Own |
| View organization activity log | D-01 → ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Edit or delete activity log entries | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

---

## 4. Special rules (apply to every role)

1. **Nobody can change their own role**, and nobody can raise anyone to OWNER except through "transfer ownership" by the current OWNER.
2. **ADMIN cannot touch the OWNER** (no role change, no disable).
3. **Disabled member** (`memberships.status = 'disabled'`): loses all access to that organization immediately, but their name stays on old tasks, comments and logs.
4. **Disabled account** (`profiles.status = 'disabled'`, set by PLATFORM_ADMIN): the person cannot use any organization.
5. **Suspended organization** (`organizations.status = 'suspended'`): nobody in it (including OWNER) can open its data; they see an "organization suspended" page.
6. **Expired subscription**: behaviour decided in `12-billing-subscriptions.md` (D-25; recommended: read-only).
7. Hiding a button in the screen is **never** the protection. Every permission above is checked on the server **and** in the database (see `03-architecture.md` and `06-authorization-rls.md`).

---

## 5. Decisions raised in this file

| # | Question | Recommended default | Why |
|---|---|---|---|
| D-01 | Can PLATFORM_ADMIN read an organization's business data for support? (none / read-only with audit log / only with the organization's permission) | **None in V1.** Later: read-only access only after the OWNER grants time-limited permission, with every view logged. | Businesses trust the platform more; fewer ways for data to leak; support can be done by screen-sharing in V1. |
| D-02 | MANAGER's financial access | **View invoices and payments only.** No creating/editing invoices or payments, no expenses, no financial reports. | Managers need to know whether a customer paid before starting more work, but money changes belong to the ACCOUNTANT/OWNER. |
| D-03 | ACCOUNTANT's access to projects and tasks | **View only** (projects, tasks, comments, work reports). | The accountant needs to see what work was done to invoice it, but should not change the work plan. |
| D-05 | Can EMPLOYEE see customer info? | **Yes, read-only basic info** (name, phone, address) — only customers of projects they are a member of. | Employees often need to call or visit the customer; they never need the full customer list. |
| D-06 | Can CLIENT see tasks? | **Organization setting "Clients can see tasks", off by default.** When on: title, status, due date only. | Some businesses want transparency, others don't; a setting satisfies both with little extra work. |
| D-07 | Can EMPLOYEE create tasks? | **No.** They update status and comment on assigned tasks. | Keeps work planning with managers; avoids clutter. |
| D-08 | Can ACCOUNTANT create/edit customers? | **Yes** (not archive). | Accountants often invoice walk-in customers who are not in the system yet. |
| D-09 | Can MANAGER invite users? | **No.** Only OWNER/ADMIN. | Adding people affects plan limits and security; keep it with top roles. |
| D-20 | Can EMPLOYEE submit expenses (claims with approval)? | **No in V1.** | Needs an approval workflow; postpone to V2. |
| D-21 | Can CLIENT upload files? | **No in V1.** | Avoids storage abuse and unscanned files from outside; clients can send files by WhatsApp/email and staff upload them. |
| D-22 | Can EMPLOYEE upload documents? | **Yes**, to tasks assigned to them and projects they are a member of. | Field workers need to upload photos of finished work. |
| D-24 | How is an organization deleted? | OWNER requests deletion → organization is hidden (`pending_deletion`) → PLATFORM_ADMIN permanently deletes data and files after 30 days. | Protects against accidental or malicious deletion; gives time to undo. |
| D-25 | What happens when a subscription expires? | **Read-only** (can view and download, cannot create/edit) until renewed; PLATFORM_ADMIN may suspend after 30 days unpaid (D-49). | Businesses keep access to their records (fair and legally safer) but have a reason to pay. |
| D-29 | Can one CLIENT login be linked to several customers of the same organization? | **No in V1** — one customer per client membership. | Keeps client security rules simple; rare case. |
| D-30 | Do CLIENTs see platform announcements? | **No** — announcements are for business users only. | Announcements are about the software (maintenance, new features), not relevant to the business's own customers. |
