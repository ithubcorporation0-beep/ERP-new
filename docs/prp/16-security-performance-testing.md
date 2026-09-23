# 16 — Security, Performance & Testing

> This file is the checklist used in Step 23 (security audit) and the testing plan used in every step.
> Each item says **how** it is done in this project, so it can be checked.

---

## Part 1 — Security checklist

| # | Area | How we do it | Checked by |
|---|---|---|---|
| S-01 | **Authentication** | Clerk (D-62): email + password, email verification required, password rules (D-35), bot protection, new-device check; server verifies the user with Clerk's `auth()` on every request; Supabase verifies the Clerk token itself (third-party auth) | Manual + E2E |
| S-02 | **Authorization** | `requireMembership` / `requirePlatformAdmin` in every layout, page and Server Action; roles only from `memberships` / `platform_admins` | Code review + tests |
| S-03 | **RLS** | Enabled on **every** table in `public`; policies per action, `to authenticated`; no policy for `anon` | SQL query listing tables without RLS = must return 0 rows; pgTAP |
| S-04 | **Tenant isolation** | Helpers require active membership; composite foreign keys; `organization_id` immutable | pgTAP "org A vs org B" suite |
| S-05 | **Server-side validation** | Zod on every Server Action and Route Handler input; database constraints repeat the key rules | Unit tests of schemas |
| S-06 | **Never trust browser values** | Totals, statuses, numbers, `organization_id`, `created_by`, prices on issued documents are set by server/database; column grants block them | pgTAP (try to update them → refused) |
| S-07 | **Secret management** | Secrets only in `.env.local` and Vercel; `.env*.local` in `.gitignore`; only 4 `NEXT_PUBLIC_` variables; `admin.ts` imports `server-only` | `git grep` for key patterns; build check |
| S-08 | **Admin client use** | Only the uses listed in `03-architecture.md` §4.1, each after a permission check and logged | Code search for `admin.ts` imports |
| S-09 | **File security** | Private bucket, paths start with `organization_id`, storage policies tied to `documents` RLS, signed URLs 5 min, type/size checks at server and bucket, no SVG/HTML uploads | Tests in `10-documents.md` §10 |
| S-10 | **API security** | Publishable key gives no rights; `private` schema not exposed; RPC functions check permissions themselves, `execute` revoked from `anon` where not needed | pgTAP as `anon` and as wrong role |
| S-11 | **SQL injection** | No SQL built from strings in the app; Supabase client and RPC parameters only; database functions use parameters, no dynamic SQL (or `format()` with `%I/%L` if ever needed) | Code review |
| S-12 | **XSS** (injecting scripts into pages) | React escapes all text; **no** `dangerouslySetInnerHTML` with user content; comments, notes and announcements are plain text; no SVG uploads | Code search |
| S-13 | **CSRF** (another site submitting forms as the user) | Server Actions only accept POST and Next.js checks the Origin header; logout is POST; cookies `SameSite=Lax` | Next.js built-in; manual check |
| S-14 | **Open redirects** | `next=` parameters must be relative paths starting with `/` (not `//`) | Unit test |
| S-15 | **Rate limiting** | Clerk's limits and bot protection for signup/login/reset/codes; own limits (D-53) for: invitations (e.g. 20/hour per organization), resend (5/day per invite), upload preparation (60/hour per user), slug checks | Manual test: exceed → friendly message |
| S-16 | **Audit logging** | Trigger on every business table; append-only; no secrets | pgTAP: update/delete log → refused |
| S-17 | **Error handling** | Friendly messages only; database errors mapped by code (`lib/errors.ts`); stack traces only in server logs; `error.tsx` pages | Manual: force an error |
| S-18 | **Session security** | Clerk's secure session cookies and short-lived tokens; logout via Clerk; disabled account also banned in Clerk | Manual |
| S-19 | **Security headers** (in `next.config.ts`) | `Content-Security-Policy` (self + Supabase URL; no inline scripts except what Next.js needs), `X-Frame-Options: DENY` / `frame-ancestors 'none'` (no embedding in other sites), `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` (camera only where uploads need it), `Strict-Transport-Security` | Online header checker on the preview URL |
| S-20 | **Enumeration** | Same message for "email exists / doesn't exist"; 404 (not 403) for other orgs' IDs; UUIDs | Manual |
| S-21 | **CSV exports** (D-55) | Cells starting with `=`, `+`, `-`, `@` are prefixed with `'` so Excel does not run them as formulas; export limited to roles that can see the data | Unit test |
| S-22 | **Dependencies** | `npm audit` before launch; only announced packages (rule 11). Known: 13 moderate warnings from an old `uuid` copy inside `@clerk/ui` (2026-09-23; the offered fix downgrades Clerk) — re-check in Step 23 | Command |
| S-23 | **Production settings** | Separate prod Supabase project (D-56), email confirmation on, custom SMTP, redirect URLs only for real domains, `/health` page removed, seed data never applied to prod, Supabase "Security Advisor" (dashboard lint) shows no errors | Step 24 checklist |

## Part 2 — Performance

| Topic | How |
|---|---|
| Indexes | Every index in `04-database.md` (all start with `organization_id`); Supabase "Performance Advisor" checked in Step 23 |
| RLS speed | `(select private.current_user_id())` wrapped; helper functions `stable`; policies filter on indexed columns |
| Pagination | Every list 25 rows (logs 50), done in the database with `range`; total count only where shown |
| Server-side queries | Data loaded in Server Components; select **only needed columns**, never `select *` on big tables |
| No whole tables | Dashboards and reports use database `sum`/`count`/`group by` (views or RPC functions); never load all invoices into the app to add them up |
| Caching | Tenant pages are dynamic (no shared cache); static public pages (home, pricing) are cached; `revalidatePath` after changes |
| Files | Direct browser → Storage uploads; downloads via signed URLs straight from Supabase; images shown with `next/image` where useful; logo ≤ 1 MB |
| Lazy loading | Charts and heavy components (e.g. rich date pickers) loaded only on pages that use them; `loading.tsx` skeletons |
| Regions | Supabase and Vercel functions in the same region near Pakistan (D-57) |
| Exports | CSV built in the database/server in chunks, max 10,000 rows per export in V1 |

## Part 3 — Testing

### 3.1 Test types and how to run them

| Type | Tool | What | Command (you run in PowerShell) |
|---|---|---|---|
| Lint | ESLint | Code-style and common mistakes | `npm run lint` |
| Build | Next.js | Type errors, missing imports, server-only violations | `npm run build` |
| Unit | Vitest | Zod schemas, money formatting, permission map, redirect safety, CSV escaping | `npm run test` |
| Database / RLS | pgTAP (SQL tests in `supabase/tests/`) | Tenant isolation, role rules, triggers, money functions, invoice numbering | `npx supabase test db` (exact form confirmed in Step 8 — D-59) |
| Browser (optional) | Playwright | Login → create invoice → record payment smoke test | `npx playwright test` (D-61) |
| Manual | Checklists at the end of every step | What to click, what you should see | — |

**D-59 — where the database tests run:** on the **cloud dev project** (no Docker needed on Windows). Each test runs inside a transaction that is rolled back at the end, so it leaves no data behind. Local Supabase in Docker is optional for later.

### 3.2 Required test groups

1. **Auth tests**: signup → confirm → login; wrong password; reset password; disabled account → disabled page; logged-out access to `/app` → login.
2. **Authorization tests**: each role opens each module URL → allowed or "No access" per `07-panels.md`; each Server Action called with a forbidden role → refused.
3. **RLS tests** (pgTAP) — at least those in `06-authorization-rls.md` §7, especially **"user of org A tries to read org B"** on every business table.
4. **CRUD tests** per module: create, edit, archive/restore, search, filter, pagination.
5. **Finance calculation tests**: `09-finance.md` §11.
6. **File-access tests**: `10-documents.md` §10.
7. **Mobile tests**: Chrome DevTools phone view (360px) + a real phone: menu drawer, My Tasks, status change, photo upload, invoice view.
8. **Production build tests**: `npm run build` clean; preview deployment works; env variables present; no console errors.

### 3.3 Role-based test matrix

Expected result when each role tries the action inside **their own** organization (✅ allowed, 👁 view only, ❌ refused/No access, "own" = only own/linked/assigned items). Plus row 1 for another organization.

| # | Test | Owner | Admin | Manager | Accountant | Employee | Client | Platform Admin (not a member) |
|---|---|---|---|---|---|---|---|---|
| 1 | Open any page of **another** organization | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 2 | View team list | ✅ | ✅ | 👁 | ❌ | ❌ | ❌ | ❌ |
| 3 | Invite a member | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 4 | Change own role | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 5 | Change OWNER's role / disable OWNER | ❌ (self) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 6 | Create customer | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 7 | View customer list | ✅ | ✅ | ✅ | ✅ | own projects' customers | own only | ❌ |
| 8 | Create project / task | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 9 | View tasks | ✅ | ✅ | ✅ | 👁 | own | ❌ (✅ own if D-06 on) | ❌ |
| 10 | Change task status | ✅ | ✅ | ✅ | ❌ | own | ❌ | ❌ |
| 11 | Create / issue invoice | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 12 | View invoices | ✅ | ✅ | 👁 | ✅ | ❌ | own, not drafts | ❌ |
| 13 | Edit an issued invoice | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 14 | Record / reverse payment | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 15 | Delete a payment | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 16 | View / create expenses | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 17 | Download a document | ✅ | ✅ | ✅ (not expenses) | ✅ (finance + view) | own tasks/projects | own + visible only | ❌ |
| 18 | Financial reports | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 19 | Activity log | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ (platform log only) |
| 20 | Organization settings | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 21 | Billing page | ✅ | ❌ (plan info on settings) | ❌ | ❌ | ❌ | ❌ | manages via /platform |
| 22 | Suspend organization / manage plans | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| 23 | Any write while subscription expired | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| 24 | Anything while organization suspended | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (platform only) |

Test data: `supabase/seed.sql` (dev project only) creates **two organizations**, each with one user per role, two customers each with a client login, projects, tasks, invoices, payments, expenses and documents — so every row of this matrix can be tried quickly. Seed users use obviously fake emails on a test domain and a documented dev-only password; they never exist in production.

## Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-55 | CSV export in V1 | **Yes** for customers, invoices, payments, expenses and financial reports, only for roles that can see that data; max 10,000 rows. | Accountants need data in Excel; cheap to build safely. |
| D-59 | Where database tests run | **Cloud dev project**, each test rolled back; no Docker needed. | You use Windows; Docker Desktop is heavy and a common source of setup problems. |
| D-61 | Automated browser (Playwright) tests | **A small smoke suite in Step 23**; manual checklists before that. | Gives a safety net before launch without slowing early steps. |

Referenced: D-35, D-53, D-56, D-57.
