# MASTER PROMPT — Multi-Tenant SaaS Business Management Software

---

## 0. WHO I AM

I am a VIBE CODER, not an expert programmer. I will mostly run commands, test, and report errors back.
Claude Code creates and edits the files itself. I should only have to do things that happen outside the code (dashboards, accounts, keys, clicking "Deploy").
Follow every rule in `CLAUDE.md`.

---

## 1. PROJECT CONCEPT — THIS IS A SaaS

I want ONE online software (example: `mysoftware.com`) that MANY different businesses can sign up for and use. Each business that signs up is an **Organization** (also called a "tenant").

- All organizations use the same website, the same login page, the same backend and the same database.
- The data of Organization A must NEVER be visible to Organization B. This is the most important security rule of the whole project.
- Inside one organization, each person only sees what their role allows.

### 1.1 Two levels of roles

**Platform level (the software owner — me):**

| Role | Purpose |
|---|---|
| PLATFORM_ADMIN | Runs the whole SaaS: sees the list of organizations, their plan and status, can suspend/activate an organization, manages subscription plans, platform settings and platform announcements. By default does NOT read an organization's business data (customers, invoices, etc.). [DECISION REQUIRED: support access to tenant data — none / read-only with audit log / only with the organization's permission] |

**Organization level (inside each business):**

| Role | Purpose |
|---|---|
| OWNER | The person who created the organization. Full control of that organization, including billing/subscription and deleting the organization. Exactly one owner per organization (ownership can be transferred). |
| ADMIN | Runs the organization day-to-day. Everything except billing, deleting the organization, and changing the owner. |
| MANAGER | Manages customers, projects, tasks and team work. Financial access: [DECISION REQUIRED] |
| ACCOUNTANT | Manages invoices, payments, expenses and financial reports. Access to projects/tasks: [DECISION REQUIRED] |
| EMPLOYEE | Sees and updates only the tasks/projects assigned to them. |
| CLIENT | An external customer of the organization. Sees only the records of the customer account they are linked to. |

> Note: the original plan used SUPER_ADMIN as a role inside the business. In a SaaS that is wrong — "super admin" is the platform owner, and each business gets its own OWNER.

### 1.2 Memberships (how users connect to organizations)

- A user account (Supabase Auth) is separate from organization access.
- A `memberships` table connects `user` + `organization` + `role`.
- One user can belong to more than one organization, with a different role in each (example: an accountant working for two businesses).
- The role is stored ONLY in the database `memberships` table. It must NEVER be read from user-editable metadata (`user_metadata`), because users can change that themselves.
- A CLIENT membership must also be linked to one `customer` record of that organization.

### 1.3 Login flow

```
/login
  ↓ Supabase Auth checks email + password
  ↓ server reads the user's profile + memberships
  ↓ account disabled?            → show "account disabled" page
  ↓ is PLATFORM_ADMIN?           → /platform
  ↓ no memberships?              → /onboarding (create an organization or wait for an invite)
  ↓ exactly one membership?      → /app/[orgSlug]  (panel for that role)
  ↓ more than one membership?    → /select-organization
  ↓ organization suspended?      → show "organization suspended" page
```

### 1.4 URL strategy (Version 1)

Path-based: `/app/[orgSlug]/...` (example: `/app/wajid-marble/invoices`).
Subdomains (`wajid-marble.mysoftware.com`) are postponed. [DECISION REQUIRED for later versions]

---

## 2. TECHNOLOGY (fixed — do not change without asking me)

Frontend: Next.js (App Router), TypeScript, Tailwind CSS, shadcn/ui
Backend: Supabase — PostgreSQL, Supabase Auth, Supabase Storage, Row Level Security
Validation: Zod (server-side validation of every form and action)
Database changes: Supabase CLI migrations in `supabase/migrations/`
Code hosting: GitHub
Deployment: Vercel (auto-deploy from GitHub)

Rules about versions:
- Before writing setup code, check the currently installed versions (`package.json`) and follow the official docs for THOSE versions. Do not rely on memory for Next.js or Supabase setup.
- Use `@supabase/ssr` for auth in Next.js. Do NOT use the deprecated `@supabase/auth-helpers` packages.
- Newer Next.js versions renamed `middleware.ts` to `proxy.ts`. Use whichever one the installed version expects.
- Supabase keys: use the new **publishable** key (browser-safe) and **secret** key (server-only). Only use the legacy `anon` / `service_role` keys if my Supabase project does not show the new ones.

---

## 3. YOUR ROLE

Act as: Senior Software Architect, SaaS Product Manager, Database Architect, Security Engineer, UX/UI Architect, Full-Stack Engineer, DevOps Engineer.

At this stage your job is ONLY to write the PRP (Product Requirements Plan). Do NOT write application code, do NOT create the database, do NOT install packages.

---

## 4. HOW TO WRITE THE PRP

The PRP is too big for one answer, so write it as separate files inside `docs/prp/`, in batches, only when I ask for each batch:

| Batch | Files |
|---|---|
| A | `01-overview.md`, `02-roles-permissions.md`, `03-architecture.md`, `04-database.md` |
| B | `05-auth-onboarding.md`, `06-authorization-rls.md`, `07-panels.md`, `08-workflows.md`, `09-finance.md`, `10-documents.md` |
| C | `11-notifications-audit.md`, `12-billing-subscriptions.md`, `13-apis-env.md`, `14-ui-ux.md`, `15-folder-structure.md`, `16-security-performance-testing.md`, `17-deployment.md` |
| D | `18-phases.md`, `19-decisions-required.md` |

General rules for every file:
- Do not invent business requirements. If something is unknown, write `[DECISION REQUIRED]` and also give your **recommended default** with one line explaining why.
- Every `[DECISION REQUIRED]` must also be collected in `19-decisions-required.md`, numbered (D-01, D-02 …), grouped by: blocks the database / blocks a later phase / can wait.
- Write in simple English. When you use a technical word for the first time, explain it in one short sentence.
- Keep files consistent with each other (same table names, same role names everywhere).

---

## 5. WHAT EACH PRP FILE MUST CONTAIN

### 01-overview.md
- What the software is, who uses it, what problem it solves
- The SaaS model: platform vs organizations
- Main objectives and core functionality
- System boundaries (what the software does NOT do)
- Version 1 scope vs postponed features (V2 / future)

### 02-roles-permissions.md
For every role (PLATFORM_ADMIN, OWNER, ADMIN, MANAGER, ACCOUNTANT, EMPLOYEE, CLIENT):
purpose, dashboard, pages, data they can view / create / update / delete, financial access, user-management access, reporting access, settings access, billing access.

Then a full permission matrix, one row per permission, example:

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|

Do not give permissions randomly. Uncertain cells = `[DECISION REQUIRED]` + recommended default.
Also decide: fixed roles in V1 (recommended) vs custom roles per organization (future).

### 03-architecture.md
Show and explain the layers:

```
Browser
 ↓
Next.js (Vercel) — pages, layouts, Server Components, Server Actions / Route Handlers
 ↓
proxy/middleware — refreshes the session, blocks logged-out users
 ↓
Server-side authorization — checks membership + role + organization status
 ↓
Supabase client (user's session → RLS applies)   |  Supabase admin client (secret key, server-only, rare)
 ↓
PostgreSQL (RLS on every table) / Supabase Storage (policies on every bucket)
```

Explain what happens on the client side, server side and database side, and where security is enforced. List every situation where the secret-key admin client is allowed (keep this list as short as possible).

### 04-database.md
Decide which tables are really needed. Start from this list but do not use it blindly:

Platform: `organizations`, `plans`, `subscriptions`, `platform_admins`, `platform_settings`
People: `profiles`, `memberships`, `invitations`
Business: `customers`, `customer_contacts` (if needed), `projects`, `project_members`, `tasks`, `task_comments` (if needed), `services_products` (or separate tables — decide), `invoices`, `invoice_items`, `payments`, `expenses`, `expense_categories`, `documents`
System: `notifications`, `activity_logs`, `organization_settings`, `number_sequences` (for invoice numbers)

For every table: name, purpose, columns, data types, primary key, foreign keys, relationships, required/optional fields, unique constraints, indexes, status values, `created_at` / `updated_at` / `created_by`, and soft-delete strategy (`deleted_at` or archive status — decide and explain).

Mandatory SaaS rules:
- Every business table has `organization_id uuid not null` referencing `organizations`.
- Unique rules are per organization (example: invoice number unique per `organization_id`, not globally).
- Every foreign key between business tables must stay inside the same organization (explain how this is enforced).
- Money columns use `numeric(12,2)` (never float).
- Use `uuid` primary keys.

Draw the relationships, for example:

```
Organization → Membership → User
Organization → Customer → Project → Task → Assigned employee (membership)
Organization → Customer → Invoice → Invoice items
                                   → Payments
Organization → Expense → Expense category
Customer ← Client membership (client login)
```

### 05-auth-onboarding.md
Using Supabase Auth: signup, email verification, login, logout, session management (cookies via `@supabase/ssr`), password reset, profile, account status (active/disabled), protected routes.
SaaS parts:
- Signup → verify email → onboarding: create organization (name, slug, currency, timezone) → user becomes OWNER.
- Invitations: OWNER/ADMIN invites by email with a role (and a customer link for CLIENT). Invite link expires. Accepting creates the membership.
- Organization switcher for users with several memberships.
- Exactly how the role is found after login (the flow in section 1.3).
- Email sending: Supabase's built-in email is only for testing (very low hourly limit). Production needs custom SMTP. [DECISION REQUIRED: provider]

### 06-authorization-rls.md
Security at three levels: UI (hide what you can't use), server (check before every action), database (RLS — the final protection).
- Design SQL helper functions such as `is_member(org_id)`, `has_role(org_id, roles[])`, `is_platform_admin()`, `client_customer_id(org_id)`. Explain `security definer`, fixed `search_path`, and how to avoid RLS infinite recursion on `memberships`.
- Write the RLS strategy (select/insert/update/delete) for: organizations, memberships, invitations, customers, projects, tasks, invoices, invoice_items, payments, expenses, documents, notifications, activity_logs.
- Explain how we prevent: Organization A reading Organization B, unauthorized URL access, ID manipulation (changing an ID in the URL), Client A seeing Client B, Employee using admin functions, direct API calls with the public key, a user changing their own role.

### 07-panels.md
Design EVERY panel (the original plan forgot Manager, Accountant and the platform panel):
- Platform Admin panel (`/platform`): organizations, plans, subscriptions, platform users, announcements, platform audit log
- Owner/Admin panel: Dashboard, Users & Invitations, Customers, Employees/Team, Projects, Tasks, Services/Products, Invoices, Payments, Expenses, Documents, Reports, Notifications, Activity Log, Settings, Billing (Owner only)
- Manager panel
- Accountant panel
- Employee panel: Dashboard, My Profile, My Tasks, My Projects, My Documents, Notifications
- Client panel: Dashboard, My Profile, My Projects, My Tasks (if allowed), My Invoices, My Payments, My Documents, Notifications

For each module: purpose, pages, CRUD, search, filters, pagination, permissions, tables used, business rules.
For the client panel: explain the `memberships.customer_id` link and the RLS rules that limit a client to their own customer.

### 08-workflows.md
Complete workflows: organization signup/onboarding, user invitation, employee assignment, customer, project, task, invoice, payment, expense, document, notification, subscription (plan change / expiry / suspension), full business flow:

```
Customer → Project → Tasks → Completion → Invoice → Payment → Report
```

For each: who starts it, steps, which database records change, who gets notified, permissions needed, possible errors and how they are shown.

### 09-finance.md
Invoices, invoice items, payments, expenses:
- Invoice numbering per organization (format like `INV-2026-0001`, no duplicates even when two people save at the same time — explain the method).
- Subtotal, discount, tax, total, amount paid, balance, currency (per organization).
- Status values (draft, sent, partially paid, paid, overdue, void — decide).
- Can a sent invoice be edited? Can a payment be deleted or only reversed? [DECISION REQUIRED + recommendation]
- Payment methods (cash, bank transfer, JazzCash, Easypaisa, cheque, other — configurable?).
- Expense categories.
- All calculations done and validated on the server/database, never trusted from the browser.
- Do not assume any tax rule. Tax = `[DECISION REQUIRED]`.

### 10-documents.md
Supabase Storage: buckets, folder strategy (`{organization_id}/{entity}/{id}/{file}`), metadata table, upload rules, size limits, allowed file types, private buckets + signed URLs, access permissions, deletion rules, organization logo handling. No user may open a file of another organization or another client.

### 11-notifications-audit.md
Notifications: events (task assigned, project assigned, invoice created, payment recorded, document uploaded, invitation, subscription warnings, platform announcements), table design, read/unread, notification center, permissions, future email/WhatsApp.
Audit log: who, what action, which record, when, organization, before/after values (only changed fields), IP/user agent if available. Prefer database triggers so nothing is missed. Never log passwords, tokens or keys. Logs cannot be edited or deleted by normal users.

### 12-billing-subscriptions.md
- Plans (example: Free trial / Basic / Pro) and limits (users, storage, customers…) — all numbers `[DECISION REQUIRED]`.
- Trial length, what happens when a subscription expires (read-only? suspended?).
- Payment collection: Stripe does not directly support businesses registered in Pakistan (verify), so recommend for V1: **manual billing** — organization pays by bank transfer / JazzCash / Easypaisa outside the app and the PLATFORM_ADMIN activates the plan. Automated gateway (local gateway or merchant-of-record service) = future. [DECISION REQUIRED]
- How limits are enforced on the server.

### 13-apis-env.md
External APIs split into REQUIRED FOR V1 / OPTIONAL FOR V1 / FUTURE (email/SMTP, AI, WhatsApp, SMS, payment gateways, Google services, maps, accounting). Only include an API if a real feature needs it.

Environment variables split into PUBLIC and SERVER-ONLY SECRET, with: where used, public or secret, where to set locally (`.env.local`), where to set in Vercel (Project → Settings → Environment Variables, which environments). At minimum:

| Variable | Type |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | public |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | public |
| `NEXT_PUBLIC_SITE_URL` | public |
| `SUPABASE_SECRET_KEY` | secret, server-only |

Also list Supabase dashboard settings that must match (Auth → URL Configuration: Site URL and Redirect URLs for localhost and the Vercel domain).

### 14-ui-ux.md
Design style, color system (light/dark if wanted), typography, spacing, buttons, forms, tables, cards, modals, toasts, loading/empty/error states, mobile responsiveness (sidebar → drawer), accessibility. All panels share one layout system. Organization logo/name shown in the header.

### 15-folder-structure.md
Complete Next.js folder tree adapted to this project (route groups for public pages, auth pages, `/platform`, `/app/[orgSlug]`), plus `supabase/migrations`, `docs/`, tests. No unnecessary folders. Explain each folder in one line.

### 16-security-performance-testing.md
Security checklist: authentication, authorization, RLS, tenant isolation, server-side validation (Zod), secret management, file security, API security, SQL injection, XSS, CSRF (Server Actions), rate limiting (login, signup, invites), audit logging, error handling (no stack traces to users), session security, security headers, production settings.
Performance: indexes (especially on `organization_id`), pagination, server-side queries, caching, image/file optimization, lazy loading, never loading whole tables.
Testing: auth tests, authorization tests, RLS tests (including "user of org A tries to read org B"), CRUD tests, finance calculation tests, file-access tests, mobile tests, production build tests. Include a role-based test matrix. Keep testing simple enough for me to run (commands + manual checklists).

### 17-deployment.md
GitHub → Vercel flow, preview vs production deployments, environment variables per environment, separate Supabase projects for development and production [DECISION REQUIRED — recommended], running migrations on production, custom domain, backups.
Mention plan limits honestly: Vercel's free Hobby plan is for non-commercial use, and Supabase free projects pause when inactive — so a paid plan is needed before real customers use it.

### 18-phases.md
Break the build into small phases. Recommended order (improve it if needed and explain why):

1. Project setup + first Vercel deployment (deploy early, not at the end)
2. Supabase connection + environment variables
3. Database foundation: organizations, profiles, memberships, platform admins, helper functions, RLS, audit trigger base
4. Authentication: signup, email verification, login, logout, password reset
5. Onboarding + organization creation + role-based routing + app shell for every panel
6. Invitations + user management
7. Customers (+ client linking)
8. Projects + tasks (+ employee and client views)
9. Services/products catalog
10. Invoices + invoice numbering
11. Payments
12. Expenses
13. Documents (storage)
14. Notifications
15. Dashboards + reports
16. Activity log viewer
17. Platform admin panel + plans/subscriptions (manual billing)
18. Security audit + RLS test suite
19. Production launch

For each phase: objective, files/modules involved, dependencies, exact deliverables, ACTION REQUIRED FROM ME (if any), test checklist, definition of done.

### 19-decisions-required.md
Every open decision, numbered, grouped, each with options and your recommended default.

---

## 6. IMPORTANT

- Do NOT start coding the application.
- Do NOT create the database yet.
- Do NOT install packages.
- Do NOT invent missing business requirements.
- Write only the batch I ask for, then stop and wait.
