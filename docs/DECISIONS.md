# DECISIONS

A log of every decision made for this project: what was decided, why, and when.
Open questions live in `docs/prp/19-decisions-required.md` (written in Step 4). Once you answer them, they move here.

| # | Date | Decision | Why | Decided by |
|---|---|---|---|---|
| 0-01 | 2026-09-23 | The existing `docs/MASTER_PROMPT.md` was replaced with PART B of the all-in-one prompt (only difference: an old header note that pointed to `BUILD_GUIDE.md` was removed). | The build order now lives in `docs/BUILD_ORDER.md`, so the old note was wrong. | Claude (following the all-in-one prompt) |
| 0-02 | 2026-09-23 | PRP decisions are numbered D-01, D-02 … starting in batch A. Numbers stay the same in later batches and in `19-decisions-required.md`. | So you can answer "D-12: use recommendation" and everyone knows which one. | Claude |
| 1-01 | 2026-09-23 | Fixed roles in V1 (7 roles); custom roles later. | Fully testable, simple security rules. | Claude (PRP 02) |
| 1-02 | 2026-09-23 | Only 3 uses of the secret-key admin client allowed: disable/enable auth accounts (platform admin), Supabase invite email (only if chosen in batch B), permanent org deletion. Everything else uses the user's session + `security definer` DB functions. | The secret key bypasses all security rules. | Claude (PRP 03) |
| 1-03 | 2026-09-23 | Business data is loaded by Server Components, not from the browser, in V1. | One clear, checkable data path. | Claude (PRP 03) |
| 1-04 | 2026-09-23 | Soft delete per record type (archive / void / reverse / disable / real delete) instead of a `deleted_at` column everywhere. | A forgotten `deleted_at` filter would leak "deleted" data. | Claude (PRP 04) |
| 1-05 | 2026-09-23 | Composite foreign keys `(organization_id, x_id)` on every business link. | Database itself guarantees links stay inside one organization. | Claude (PRP 04) |
| 1-06 | 2026-09-23 | Status values as `text` + check constraint, not Postgres enums. | Easier to change later. | Claude (PRP 04) |
| 1-07 | 2026-09-23 | One `services_products` table with `item_type`. | Services and products behave the same without stock control. | Claude (PRP 04) |
| 1-08 | 2026-09-23 | "Overdue" is calculated when shown, not stored. | No daily job needed; never stale. | Claude (PRP 04) |
| 1-09 | 2026-09-23 | Added tables `subscription_payments` and `platform_announcements`; `customer_contacts` not in V1 (D-16). | Manual billing needs payment records; announcements are not per-user notifications. | Claude (PRP 04) |
| 1-10 | 2026-09-23 | Client-readable tables hold no internal-only columns (RLS is per row, not per column). | Clients could otherwise read hidden columns via the public API. | Claude (PRP 04) |
| 1-11 | 2026-09-23 | Invoice customer details are snapshotted (`bill_to`) when issued; catalog items are copied into invoice lines. | Old invoices never change when customers or prices change. | Claude (PRP 04) |
| 2-01 | 2026-09-23 | All organization panels share one set of routes under `/app/[orgSlug]`; menus, server checks and RLS decide what each role sees. | One place per rule; no duplicated pages per role. | Claude (PRP 07) |
| 2-02 | 2026-09-23 | RLS helper functions live in a `private` schema (not exposed by the API); sensitive changes go through `security definer` RPC functions with no direct table write policies; column grants limit updatable columns. | Smallest possible attack surface. | Claude (PRP 06) |
| 2-03 | 2026-09-23 | Invitation accept requires the logged-in verified email to equal the invited email; tokens stored only as SHA-256 hashes. | A forwarded or leaked link cannot be used by someone else. | Claude (PRP 05) |
| 2-04 | 2026-09-23 | Void invoice only when it has no completed payments; expenses editable while recorded (logged), voided instead of deleted. | Money received always tied to a valid invoice; full history kept. | Claude (PRP 09) |
| 2-05 | 2026-09-23 | Files upload directly from browser to Storage with a server-created signed upload URL, then the server confirms and writes the `documents` row; storage read policy is tied to `documents` RLS. | Vercel limits request size to ~4.5 MB; tying storage to the documents table applies every role rule to files. | Claude (PRP 10) |
| 2-06 | 2026-09-23 | Subscription expiry is checked live from dates (no background job) in V1. | Fewer moving parts; cannot fail silently. | Claude (PRP 08) |
| 3-01 | 2026-09-23 | Notifications created by database triggers/functions in the same transaction; bell refreshes on navigation + every 60 s (no realtime in V1). | Never forgotten, never for undone changes; simplest reliable option. | Claude (PRP 11) |
| 3-02 | 2026-09-23 | Supabase pg_cron used only for small database clean-ups (e.g. old read notifications). | Built into Supabase; no extra service. | Claude (PRP 11) |
| 3-03 | 2026-09-23 | Audit trigger reads IP/user agent from headers forwarded by our server client; labelled "reported IP", never used for security. | Useful context without trusting spoofable data. | Claude (PRP 11) |
| 3-04 | 2026-09-23 | ADMIN can see plan name, limits and usage (not payments). | ADMIN invites people and needs to know limits. | Claude (PRP 12, updated 02/06/07) |
| 3-05 | 2026-09-23 | Pending invitations count toward user/client limits; plans differ only by limits in V1. | Prevents over-inviting; simpler plans. | Claude (PRP 12) |
| 3-06 | 2026-09-23 | Module code lives in `src/features/<module>/` (actions, queries, schemas, components); pages stay thin. | Everything about one module in one place. | Claude (PRP 15) |
| 3-07 | 2026-09-23 | `NEXT_PUBLIC_SITE_URL` left empty in Vercel Preview; code falls back to Vercel's automatic preview URL. | Auth links work on every preview link. | Claude (PRP 13) |
| 4-01 | 2026-09-23 | Build order kept as in the brief, with 6 improvements: tests grow every phase, audit trigger added with each table, notification hooks as TODO comments until Phase 14, `org_writable`/`org_limits` stubs from Phase 3, rate-limit table in Phase 6, deploy after every phase. | Earlier security testing, no rewrites later. | Claude (PRP 18) |

## Answers to PRP decisions (2026-09-23)

You replied "yes" to the decision list = use Claude's recommendation for every decision. Full options: `docs/prp/19-decisions-required.md`.

| # | Date | Question | Decision | Decided by |
|---|---|---|---|---|
| D-01 | 2026-09-23 | Can PLATFORM_ADMIN read an organization's business data (support)? | never — Never in V1 (c later) | You ("use recommendation") |
| D-02 | 2026-09-23 | MANAGER's financial access | view invoices & payments — View invoices & payments only; no expenses or financial reports | You ("use recommendation") |
| D-03 | 2026-09-23 | ACCOUNTANT's access to projects/tasks | view only | You ("use recommendation") |
| D-04 | 2026-09-23 | Subdomains per organization later | keep `/app/[orgSlug]` — Keep paths; revisit after launch | You ("use recommendation") |
| D-05 | 2026-09-23 | Can EMPLOYEEs see customer info? | basic info of their projects' customers | You ("use recommendation") |
| D-06 | 2026-09-23 | Can CLIENTs see tasks? | organization setting, off by default — Setting, off by default; title/status/due date only | You ("use recommendation") |
| D-07 | 2026-09-23 | Can EMPLOYEEs create tasks? | no | You ("use recommendation") |
| D-08 | 2026-09-23 | Can ACCOUNTANTs create/edit customers? | yes (not archive) | You ("use recommendation") |
| D-09 | 2026-09-23 | Can MANAGERs invite users? | no | You ("use recommendation") |
| D-10 | 2026-09-23 | Tax model | optional tax % per line + org default rate + label — default 0%, no tax law assumed | You ("use recommendation") |
| D-11 | 2026-09-23 | Discount model | amount per line — Amount per line, tax after discount | You ("use recommendation") |
| D-12 | 2026-09-23 | Currency | one per organization, locked after first invoice — default PKR | You ("use recommendation") |
| D-13 | 2026-09-23 | Invoice number format | `INV-2026-0001`, yearly restart, given at issue — with editable prefix | You ("use recommendation") |
| D-14 | 2026-09-23 | Payment rules | one invoice per payment, no overpayment, no advances — in V1 | You ("use recommendation") |
| D-15 | 2026-09-23 | Payment methods | fixed list (cash, bank transfer, JazzCash, Easypaisa, cheque, card, other) — Fixed list + reference field | You ("use recommendation") |
| D-16 | 2026-09-23 | Several contact people per customer? | one contact on the customer — in V1 | You ("use recommendation") |
| D-17 | 2026-09-23 | Internal projects (no customer) and tasks without a project? | both allowed | You ("use recommendation") |
| D-18 | 2026-09-23 | Project budget field | not in V1 | You ("use recommendation") |
| D-19 | 2026-09-23 | Stock / inventory for products | no | You ("use recommendation") |
| D-20 | 2026-09-23 | Employee expense claims with approval | not in V1 | You ("use recommendation") |
| D-21 | 2026-09-23 | Can CLIENTs upload files? | no — No in V1 | You ("use recommendation") |
| D-22 | 2026-09-23 | Can EMPLOYEEs upload documents? | yes, to their tasks/projects | You ("use recommendation") |
| D-23 | 2026-09-23 | Invitation expiry | 7 days | You ("use recommendation") |
| D-24 | 2026-09-23 | How an organization is deleted | OWNER request → hidden → permanently deleted by PLATFORM_ADMIN after 30 days | You ("use recommendation") |
| D-25 | 2026-09-23 | What happens when a subscription expires? | read-only | You ("use recommendation") |
| D-26 | 2026-09-23 | Interface language | English only — English in V1 | You ("use recommendation") |
| D-27 | 2026-09-23 | Retention of logs / notifications | Logs forever; read notifications deleted after 90 days | You ("use recommendation") |
| D-28 | 2026-09-23 | Can the organization slug change? | only PLATFORM_ADMIN on request | You ("use recommendation") |
| D-29 | 2026-09-23 | One client login linked to several customers? | one customer per client login | You ("use recommendation") |
| D-30 | 2026-09-23 | Do CLIENTs see platform announcements? | no | You ("use recommendation") |
| D-31 | 2026-09-23 | Can an issued invoice be edited? | no — void + duplicate | You ("use recommendation") |
| D-32 | 2026-09-23 | Can a payment be deleted? | no — reverse only | You ("use recommendation") |
| D-33 | 2026-09-23 | Email provider (production SMTP + invitation emails) | Resend (needs a domain you own) | You ("use recommendation") |
| D-34 | 2026-09-23 | How invitations are delivered | copy-link always + email via our provider | You ("use recommendation") |
| D-35 | 2026-09-23 | Password rules | ≥ 8 chars with a letter and a number — + leaked-password check on paid plan | You ("use recommendation") |
| D-36 | 2026-09-23 | Who can sign up? | open signup with trial (PLATFORM_ADMIN can switch off) | You ("use recommendation") |
| D-37 | 2026-09-23 | Max organizations one user can own | 3 (PLATFORM_ADMIN can raise) | You ("use recommendation") |
| D-38 | 2026-09-23 | Two-factor login | not in V1 — ; V2 starts with PLATFORM_ADMIN | You ("use recommendation") |
| D-39 | 2026-09-23 | Change email from profile | not in V1 | You ("use recommendation") |
| D-40 | 2026-09-23 | Invoice PDF / emailing | print view + browser "Save as PDF" — in V1 | You ("use recommendation") |
| D-41 | 2026-09-23 | Basis of "income vs expenses" report | cash basis (received − expenses) + invoiced shown | You ("use recommendation") |
| D-42 | 2026-09-23 | Do CLIENTs see void invoices? | yes, stamped VOID | You ("use recommendation") |
| D-43 | 2026-09-23 | File size and types | 10 MB; PDF, JPEG, PNG, WEBP, DOCX, XLSX, CSV, TXT | You ("use recommendation") |
| D-44 | 2026-09-23 | Logo storage | separate public-read bucket for logos only | You ("use recommendation") |
| D-45 | 2026-09-23 | Profile photos | not in V1 (initials) | You ("use recommendation") |
| D-46 | 2026-09-23 | Inviting a disabled member | accepting re-enables their membership | You ("use recommendation") |
| D-47 | 2026-09-23 | Plan names, prices, currency, limits (users, client logins, customers, storage) | STILL OPEN — suggested shape: trial / basic / pro in PKR | OPEN — waiting for you |
| D-48 | 2026-09-23 | Trial length | 14 days (changeable in platform settings) | You ("use recommendation") |
| D-49 | 2026-09-23 | Timeline after expiry | read-only at once, may suspend after 30 days, never auto-delete | You ("use recommendation") |
| D-50 | 2026-09-23 | Automated payment gateway | manual billing in V1 — ; evaluate local gateway / merchant of record later | You ("use recommendation") |
| D-51 | 2026-09-23 | Dark mode | light only — Light only in V1 | You ("use recommendation") |
| D-52 | 2026-09-23 | Product name, domain, brand colour | STILL OPEN — working name and neutral blue until then | OPEN — waiting for you |
| D-53 | 2026-09-23 | Rate-limit method | small table in private schema | You ("use recommendation") |
| D-54 | 2026-09-23 | Error monitoring service | Vercel logs only — ; add Sentry with paying customers | You ("use recommendation") |
| D-55 | 2026-09-23 | CSV export in V1 | yes, finance lists + reports for allowed roles — Yes, max 10,000 rows | You ("use recommendation") |
| D-56 | 2026-09-23 | Separate Supabase projects for dev and prod | yes | You ("use recommendation") |
| D-57 | 2026-09-23 | Hosting region | Mumbai (`ap-south-1` / `bom1`) — verify availability | You ("use recommendation") |
| D-58 | 2026-09-23 | Backups | Supabase Pro daily + monthly manual export | You ("use recommendation") |
| D-59 | 2026-09-23 | Where database tests run | cloud dev project, rolled back | You ("use recommendation") |
| D-60 | 2026-09-23 | Email / WhatsApp notifications | V2 | You ("use recommendation") |
| D-61 | 2026-09-23 | Automated browser tests | small Playwright smoke suite in Step 23 | You ("use recommendation") |

## Setup decisions

| # | Date | Decision | Why | Decided by |
|---|---|---|---|---|
| 5-01 | 2026-09-23 | Next.js **16.3** (latest). In this version the request-filter file is `src/proxy.ts` (not `middleware.ts`) and error pages receive `retry()`. | Latest stable; follows the installed version's own docs in `node_modules/next/dist/docs`. | Claude |
| 5-02 | 2026-09-23 | shadcn/ui with **Radix** base and **Nova** preset (Lucide icons, Geist font), neutral colours with **blue** as primary until D-52. | Matches PRP 14 (Radix accessibility, Geist, neutral blue). | Claude |
| 5-03 | 2026-09-23 | Working product name **"Business Manager"**, read from `NEXT_PUBLIC_APP_NAME` (falls back to the working name). | D-52 still open; changing the name later is one setting. | Claude |
| 5-04 | 2026-09-23 | Kept `AGENTS.md` created by Next.js (notes for AI assistants about Next.js 16). With `AGENTS.md` present, `next dev` only updates that file and never touches `CLAUDE.md`. | Keeps `CLAUDE.md` exactly as written. | Claude |
| 5-05 | 2026-09-23 | App created in a temporary folder and copied in, because `create-next-app` refuses a folder that already has files. Removed the template's sample images. | Required by Step 5 ("in this folder, without deleting CLAUDE.md or docs/"). | Claude |
| 7-01 | 2026-09-23 | Supabase connection: `@supabase/ssr` 0.12 + `@supabase/supabase-js` 2.117; server identity checked with `getClaims()`; proxy also sets the "do not cache" headers that `@supabase/ssr` sends with login cookies. | Follows the installed versions' own docs; prevents one user's session being cached for another. | Claude |
| 7-02 | 2026-09-23 | If Supabase variables are missing, the proxy skips the session step instead of crashing, so public pages keep working; `/health` explains what is missing. | Vercel keeps working while variables are being added. | Claude |
| 7-03 | 2026-09-23 | Supabase CLI installed as a dev dependency (`supabase` 2.117), used with `npx supabase …`. | Same CLI version on every computer. | Claude |
| 7-04 | 2026-09-23 | Admin (secret-key) client allowed uses reduced to 2 (disable/enable accounts, permanent org deletion) because D-34 chose copy-link + our own email for invitations; temporarily also used by `/health` to validate the key. | Smallest possible use of the key that bypasses security. | Claude |
| 7-05 | 2026-09-23 | Dev Supabase project stays in **Tokyo** (created there); the production project (Step 24) will be created in **Mumbai** (D-57). | You did not choose; my recommendation (option A). Dev speed difference is small; nothing breaks. | Claude (recommendation A) |
| 8-01 | 2026-09-23 | Foundation migration: protected changes (roles, owner, invitation acceptance) are only possible inside database functions that switch on a transaction-only flag; triggers block them otherwise — even for direct database access. | Defence in depth on the most sensitive table (memberships). | Claude |
| 8-02 | 2026-09-23 | `activity_logs.actor_user_id` has no foreign key; `organizations.created_by` and similar "who" columns allow empty (set to empty if the account is deleted). | A log or a deleted account must never block a change. | Claude |
| 8-03 | 2026-09-23 | When a whole organization is permanently deleted, one platform-level log entry is kept and the logs of rows inside it are removed with it. | Matches D-24 (full deletion) while keeping a record that the deletion happened. | Claude |
| 8-04 | 2026-09-23 | `private.org_limits()` moved from Step 8 to Step 11 (first user: invitations); demo seed data moved to Step 10 (needs login pages to be useful). | Keep each step small; no unused code. | Claude |
| 8-05 | 2026-09-23 | Database tests can be run two ways: `npx supabase test db --linked` (needs Docker) **or** by pasting the test file into the Supabase SQL Editor, which shows a PASS/FAIL table ending with "51 of 51 checks passed". Tests roll back and leave no data. | You use Windows without Docker (D-59). | Claude |
| 8-06 | 2026-09-23 | `npm run db:types` regenerates `src/types/database.types.ts` from the linked project. | One command after every migration. | Claude |

## Login provider change (2026-09-23)

| # | Date | Decision | Why | Decided by |
|---|---|---|---|---|
| D-62 | 2026-09-23 | **Clerk** handles sign-up, login, email verification, password reset and new-device checks; **Supabase** keeps database, files and RLS, trusting Clerk tokens (third-party auth). | You preferred Clerk's ready-made login screens (answer: "Clerk login + Supabase data"). | You |
| 9-01 | 2026-09-23 | Database user ids are Clerk ids (`text`, e.g. `user_2abc…`); security helpers read them with `private.current_user_id()` (`auth.jwt() ->> 'sub'`), never `auth.uid()`. Step 8 migration edited (it was not applied to your project yet). | Clerk ids are not UUIDs; `auth.uid()` would fail. | Claude |
| 9-02 | 2026-09-23 | `profiles` rows are created/updated by our server right after login (`/auth/continue`) from Clerk's server data, with the admin client (allowed use #1). No Clerk webhook in V1. | Works on your computer without a public webhook address; details never come from the browser. | Claude |
| 9-03 | 2026-09-23 | Name, email, password and 2-step login are managed in Clerk's account menu; users edit only phone (and later business details) in our profile page. | One source of truth for identity. | Claude |
| 9-04 | 2026-09-23 | `src/proxy.ts` only runs `clerkMiddleware()`; every page/layout checks login and role itself. | Clerk deprecated route lists in the proxy; matches our plan (03 §2.2). | Claude |
| 9-05 | 2026-09-23 | Removed `@supabase/ssr`, the Supabase login actions/email templates and the browser Supabase client (unused in V1). Added `@clerk/nextjs`, `@clerk/ui` (shadcn theme), `zod`. | Replaced by Clerk. | Claude |
| 9-06 | 2026-09-23 | Clerk tokens need `role: authenticated` (Clerk dashboard → Supabase integration). Without it Supabase refuses everything — tested: safe failure. | Required by Supabase third-party auth. | Claude |
