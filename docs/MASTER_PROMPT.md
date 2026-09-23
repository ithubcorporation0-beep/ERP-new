# MASTER PROMPT

> **Where this file lives:** save it in your project as `docs/MASTER_PROMPT.md`. Claude Code reads it whenever a prompt in `BUILD_GUIDE.md` tells it to. The working rules for Claude Code live in `CLAUDE.md` (project root). Claude Code reads that file automatically every session.

## 0. WHO I AM

I am a VIBE CODER, not an expert programmer. I will mostly run commands, test, and report errors back. Claude Code creates and edits the files itself. I should only have to do things that happen outside the code (dashboards, accounts, keys, clicking "Deploy"). Follow every rule in `CLAUDE.md`.

## 1. PROJECT CONCEPT — THIS IS A SaaS

I want ONE online software (example: mysoftware.com) that MANY different businesses can sign up for and use. Each business that signs up is an **Organization** (also called a "tenant").

- All organizations use the same website, the same login page, the same backend and the same database.
- The data of Organization A must NEVER be visible to Organization B. **This is the most important security rule of the whole project.**
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

> **Note:** the original plan used SUPER_ADMIN as a role inside the business. In a SaaS that is wrong — "super admin" is the platform owner, and each business gets its own OWNER.

### 1.2 Memberships (how users connect to organizations)

- A user account (Supabase Auth) is separate from organization access.
- A `memberships` table connects user + organization + role.
- One user can belong to more than one organization, with a different role in each (example: an accountant working for two businesses).
- The role is stored ONLY in the database `memberships` table. It must NEVER be read from user-editable metadata (`user_metadata`), because users can change that themselves.
- A CLIENT membership must also be linked to one customer record of that organization.

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

Path-based: `/app/[orgSlug]/...` (example: `/app/wajid-marble/invoices`). Subdomains (`wajid-marble.mysoftware.com`) are postponed. [DECISION REQUIRED for later versions]

## 2. TECHNOLOGY (fixed — do not change without asking me)

- **Frontend:** Next.js (App Router), TypeScript, Tailwind CSS, shadcn/ui
- **Backend:** Supabase — PostgreSQL, Supabase Auth, Supabase Storage, Row Level Security
- **Validation:** Zod (server-side validation of every form and action)
- **Database changes:** Supabase CLI migrations in `supabase/migrations/`
- **Code hosting:** GitHub
- **Deployment:** Vercel (auto-deploy from GitHub)

**Rules about versions:**

- Before writing setup code, check the currently installed versions (`package.json`) and follow the official docs for THOSE versions. Do not rely on memory for Next.js or Supabase setup.
- Use `@supabase/ssr` for auth in Next.js. Do NOT use the deprecated `@supabase/auth-helpers` packages.
- Newer Next.js versions renamed `middleware.ts` to `proxy.ts`. Use whichever one the installed version expects.
- Supabase keys: use the new **publishable** key (browser-safe) and **secret** key (server-only). Only use the legacy `anon` / `service_role` keys if my Supabase project does not show the new ones.

## 3. YOUR ROLE

Act as: Senior Software Architect, SaaS Product Manager, Database Architect, Security Engineer, UX/UI Architect, Full-Stack Engineer, DevOps Engineer.

At this stage your job is ONLY to write the PRP (Product Requirements Plan). Do NOT write application code, do NOT create the database, do NOT install packages.

## 4. HOW TO WRITE THE PRP

The PRP is too big for one answer, so write it as separate files inside `docs/prp/`, in batches, only when I ask for each batch:

| Batch | Files |
|---|---|
| A | 01-overview.md, 02-roles-permissions.md, 03-architecture.md, 04-database.md |
| B | 05-auth-onboarding.md, 06-authorization-rls.md, 07-panels.md, 08-workflows.md, 09-finance.md, 10-documents.md |
| C | 11-notifications-audit.md, 12-billing-subscriptions.md, 13-apis-env.md, 14-ui-ux.md, 15-folder-structure.md, 16-security-performance-testing.md, 17-deployment.md |
| D | 18-phases.md, 19-decisions-required.md |

**General rules for every file:**

- Do not invent business requirements. If something is unknown, write [DECISION REQUIRED] and also give your recommended default with one line explaining why.
- Every [DECISION REQUIRED] must also be collected in `19-decisions-required.md`, numbered (D-01, D-02 …), grouped by: blocks the database / blocks a later phase / can wait.
- Write in simple English. When you use a technical word for the first time, explain it in one short sentence.
- Keep files consistent with each other (same table names, same role names everywhere).

## 5. WHAT EACH PRP FILE MUST CONTAIN

### 01-overview.md

- What the software is, who uses it, what problem it solves
- The SaaS model: platform vs organizations
- Main objectives and core functionality
- System boundaries (what the software does NOT do)
- Version 1 scope vs postponed features (V2 / future)

### 02-roles-permissions.md

For every role (PLATFORM_ADMIN, OWNER, ADMIN, MANAGER, ACCOUNTANT, EMPLOYEE, CLIENT): purpose, dashboard, pages, data they can view / create / update / delete, financial access, user-management access, reporting access, settings access, billing access.

Then a full permission matrix, one row per permission, example:

| Permission | Platform Admin | Owner | Admin | Manager | Accountant | Employee | Client |
|---|---|---|---|---|---|---|---|

Do not give permissions randomly. Uncertain cells = [DECISION REQUIRED] + recommended default. Also decide: fixed roles in V1 (recommended) vs custom roles per organization (future).

<!--
TODO: The pasted text ended here. Sections for 03-architecture.md through
19-decisions-required.md are still missing — paste the rest of section 5
(and anything after it) below this line.
-->
