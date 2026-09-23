# 03 — Architecture

> **Architecture** = how the pieces of the software are arranged and how they talk to each other.

---

## 1. The layers

```
Browser (the user's Chrome / phone)
 ↓  HTTPS
Next.js on Vercel — pages, layouts, Server Components, Server Actions / Route Handlers
 ↓
proxy / middleware — refreshes the login session, sends logged-out users to /login
 ↓
Server-side authorization — checks: logged in? account active? member of this organization?
                            membership active? organization active? role allowed for this action?
 ↓
Supabase client (user's session → RLS applies)   |   Supabase admin client (secret key, server-only, rare)
 ↓
PostgreSQL (RLS on every table)   /   Supabase Storage (policies on every bucket)
```

Words used above:

- **Next.js**: the framework (ready-made building kit) we use to build the website, in the **App Router** style (each folder under `src/app` is a page address).
- **Vercel**: the hosting company that runs our Next.js code on the internet.
- **Server Component**: a piece of a page that runs on the server, so it can read the database safely and send finished HTML to the browser.
- **Client Component**: a piece of a page that runs in the browser (buttons, forms, menus). It never holds secrets.
- **Server Action**: a function that runs on the server when a form is submitted (example: "save invoice"). The browser cannot see its code or secrets.
- **Route Handler**: a server web address that returns data or a file instead of a page (example: the email-verification callback).
- **proxy / middleware**: code that runs before every page request. Newer Next.js calls the file `proxy.ts`, older versions `middleware.ts` — we use whichever the installed version expects (checked in Step 5).
- **Supabase**: the backend service: PostgreSQL database, login system (Auth), file storage.
- **RLS (Row Level Security)**: rules inside the database that decide, for every single row, whether the current user may see or change it.
- **Session**: proof that the user is logged in, stored in a secure browser cookie.

## 2. What happens where

### 2.1 Client side (browser)

- Shows pages, forms, menus, loading spinners, toasts (small pop-up messages).
- Does **light** form checks for a nicer experience (example: "email is required") — these are **not** security.
- Uses the **browser Supabase client** (with the public *publishable* key) only for auth actions that must happen in the browser (example: listening for "logged out in another tab"). **Business data is not read from the browser in V1**; it is loaded by Server Components. This keeps one clear path for data and makes it easy to check.
- Holds **no secrets** and makes **no permission decisions**.

### 2.2 Server side (Next.js on Vercel)

1. **proxy/middleware** (every request):
   - keeps the Clerk login session fresh (`clerkMiddleware()`, D-62),
   - if the user is not logged in and the page is under `/app` or `/platform` or `/onboarding` or `/select-organization`, redirects to `/login`.
   - It does **not** decide roles. Reason: middleware can be bypassed in some situations (a real security bug in Next.js in 2025 allowed exactly that), and it runs before we know which organization is being opened. So it is only a first filter, never the real protection.
2. **Layouts and pages under `/app/[orgSlug]`** call one shared server helper, planned as:
   `requireMembership(orgSlug, allowedRoles?)` →
   - reads the logged-in user from Clerk (`auth()`, which verifies the login token) and makes sure their `profiles` row exists,
   - checks `profiles.status = 'active'`,
   - loads the membership for that **slug** from the database,
   - checks `memberships.status = 'active'` and `organizations.status = 'active'` (else "suspended" / "no access" page),
   - checks the role is in `allowedRoles` (else "no access" page),
   - returns `{ user, organization, membership }` for the page to use.
   `/platform` pages use `requirePlatformAdmin()` the same way.
3. **Server Actions** (every change) follow the same fixed recipe:
   1. validate the input with **Zod** (a library that checks data has the right shape, e.g. "amount is a positive number with max 2 decimals"),
   2. call `requireMembership(...)` with the roles allowed for this action,
   3. load any record by ID **together with** `organization_id = current organization` (never trust an ID from the browser),
   4. do the change with the **user's Supabase client** (so RLS checks it again),
   5. never accept prices, totals, statuses, `organization_id` or `created_by` from the browser — these are calculated or set by the server/database,
   6. return a simple result (`ok` / friendly error message), never a raw database error or stack trace,
   7. refresh the affected page (`revalidatePath`).
4. **Caching**: pages with organization data are always rendered per user (dynamic). We never put tenant data in a shared cache, so one organization can never receive a cached page of another.

### 2.3 Database side (Supabase PostgreSQL + Storage)

- **RLS is switched on for every table.** Even if the server code had a bug, the database refuses rows from another organization or rows the role may not see. This is the **last and strongest** protection.
- **Helper functions** in SQL (details in `06-authorization-rls.md`): `is_member(org_id)`, `has_role(org_id, roles[])`, `is_platform_admin()`, `client_customer_id(org_id)`, `can_write(org_id, roles[])`.
- **Database functions for multi-step money actions** (example: `issue_invoice(invoice_id)`, `record_payment(...)`, `reverse_payment(...)`): they run inside one **transaction** (all steps succeed together or none do), so invoice numbers never duplicate and balances never go wrong.
- **Triggers** (automatic actions the database runs on insert/update): set `updated_at`, force `created_by = current user`, recalculate invoice totals, write the activity log, create notifications.
- **Composite foreign keys** make it impossible to link a record to a record of another organization (details in `04-database.md` §2.3).
- **Storage**: the documents bucket is **private** (only organization logos use a separate public-read bucket — D-44). Files are stored under `{organization_id}/...`; storage policies check the organization folder on upload and the `documents` table's RLS on download (`10-documents.md`). Files are opened only with short-lived **signed URLs** (temporary download links that expire after a few minutes).

## 3. Where security is enforced (summary)

| Threat | UI | Server | Database |
|---|---|---|---|
| Logged-out user opens `/app/...` | — | proxy redirects to `/login`; `requireMembership` refuses | RLS returns nothing without a session |
| User of org A opens `/app/org-b/...` | Org switcher only lists own orgs | `requireMembership` → "no access" | `is_member()` false → no rows |
| User changes an ID in the URL | — | record loaded with `organization_id` filter → 404 | RLS hides rows of other orgs/customers |
| Employee calls an admin Server Action | Button hidden | role check refuses | RLS policy refuses the write |
| Someone calls Supabase directly with the public key | — | — | RLS + helper functions apply to every request |
| Client A tries to see Client B | Menu shows only "my" pages | queries filter by `client_customer_id` | RLS checks `customer_id = client_customer_id(org)` |
| User tries to change own role | No such button | Server Action refuses | No update policy lets a member change their own membership; trigger blocks self-role-change |
| Browser sends a fake total | — | total ignored, recalculated | trigger recalculates from lines |
| File of org A requested by org B | — | signed URL only created after checks | storage policy checks the org folder |

## 4. The three Supabase clients

| Client | Key used | Where it runs | RLS applies? | Used for |
|---|---|---|---|---|
| Browser client | — | — | — | Not used in V1 (login screens are Clerk's; business data is loaded on the server) |
| Server client | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` + the user's Clerk login token | Server Components, Server Actions, Route Handlers, proxy | **Yes** (acts as the logged-in user) | **Almost everything** |
| Admin client | `SUPABASE_SECRET_KEY` | Server only (file marked `server-only`, so the build fails if a browser file imports it) | **No — bypasses RLS** | Only the short list below |

### 4.1 When the admin (secret key) client is allowed — the complete list

The admin client ignores all security rules, so it is used only where there is no safe alternative. Each use:
(a) lives in one server-only file, (b) runs **after** an explicit permission check in code, (c) writes an activity log entry, (d) never returns secret data to the browser.

1. **Copying the logged-in person's name and email from Clerk into `profiles`** (on `/auth/continue`, D-62). The details come from Clerk's server with our Clerk secret key, never from the browser; only name and email are written.
2. **Permanently deleting an organization's data and files** after the 30-day waiting period (D-24) — by PLATFORM_ADMIN only.

Disabling a whole account is done with Clerk's "ban" (Clerk secret key) plus `profiles.status`; it no longer needs the Supabase secret key.

Everything else — including accepting invitations, creating an organization, issuing invoice numbers, recording payments — is done with the user's own session plus carefully written `security definer` database functions (functions that run with extra rights but check permissions themselves). Explained in `06-authorization-rls.md`.

The **Supabase CLI** (command-line tool used to apply migrations) also uses database passwords; it runs only on the developer's computer, never inside the website.

## 5. Request examples

### 5.1 Viewing the invoice list

```
Browser → GET /app/wajid-marble/invoices
  proxy: session valid? yes → refresh cookie → continue
  layout: requireMembership('wajid-marble', any role) → membership = ACCOUNTANT, org active ✓
  page:   requireMembership('wajid-marble', [OWNER, ADMIN, ACCOUNTANT, MANAGER(D-02)]) ✓
          server client: select invoices where organization_id = <org id> order by issue_date desc limit 25
  database: RLS → has_role(org, [...]) ✓ → returns only this org's rows
  → HTML sent to browser
```

### 5.2 Recording a payment

```
Browser form → Server Action recordPayment({ invoiceId, amount, date, method, reference })
  Zod: amount > 0, 2 decimals, date valid, method in list ✓
  requireMembership(orgSlug, [OWNER, ADMIN, ACCOUNTANT]) ✓
  server client: rpc('record_payment', {...})
  database function (one transaction):
     lock invoice row → check invoice belongs to org, is issued, not void
     check amount ≤ balance (D-14) → insert payment
     trigger: recalc amount_paid, balance, status → write activity log → create notification
  → { ok: true } → revalidatePath → toast "Payment recorded"
```

## 6. Environments

| Environment | Website | Database |
|---|---|---|
| Local (my computer) | `http://localhost:3000` | Supabase project `saas-app-dev` |
| Preview (every non-main branch on Vercel) | `*.vercel.app` preview link | `saas-app-dev` |
| Production (main branch) | real domain | separate Supabase production project (decision in `17-deployment.md`) |

## 7. Decisions for this file (answered 2026-09-23 — "use recommendation")

None new. This file depends on: D-01 (platform admin tenant access), D-14 (overpayment rule), D-24 (organization deletion), and D-34 (invitation delivery).
