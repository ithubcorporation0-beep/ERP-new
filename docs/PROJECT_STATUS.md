# PROJECT STATUS

Last updated: 2026-09-23

## Current stage
STAGE 3 — FOUNDATION. Logins moved to **Clerk** (D-62). Step 8 migration reworked for Clerk ids (not yet applied to your Supabase project). Step 9 (login with Clerk) built and tested here.

## Done
- [x] Rules saved in `CLAUDE.md`
- [x] Project brief saved in `docs/MASTER_PROMPT.md`
- [x] Build order saved in `docs/BUILD_ORDER.md`
- [x] Tracking files created (`PROJECT_STATUS.md`, `TODO.md`, `DECISIONS.md`)
- [x] STEP 1 — PRP batch A: `docs/prp/01-overview.md`, `02-roles-permissions.md`, `03-architecture.md`, `04-database.md`
- [x] STEP 2 — PRP batch B: `05-auth-onboarding.md`, `06-authorization-rls.md`, `07-panels.md`, `08-workflows.md`, `09-finance.md`, `10-documents.md` (+ 3 small consistency additions to `04-database.md`)
- [x] STEP 3 — PRP batch C: `11-notifications-audit.md`, `12-billing-subscriptions.md`, `13-apis-env.md`, `14-ui-ux.md`, `15-folder-structure.md`, `16-security-performance-testing.md`, `17-deployment.md` (+ cross-file consistency fixes in 01–08)
- [x] STEP 4 (part 1) — `18-phases.md`, `19-decisions-required.md`, full consistency review of all PRP files
- [x] STEP 4 (part 2) — decisions answered ("use recommendation" for all); PRP files updated; answers logged in `DECISIONS.md`
- [x] STEP 5 — Next.js 16 app created in this folder (TypeScript, App Router, Tailwind 4, ESLint, `src/`), shadcn/ui (Radix, Nova preset), home page, 404 page, error page, `.gitignore` (blocks `.env*` except `.env.example`), `.env.example`, `README.md`. `npm run lint` and `npm run build` pass.
- [ ] STEP 6 — first Vercel deployment: project imported, but the live site shows Vercel's 404 because GitHub has no `main` branch yet (default branch contains only `docs/`). Waiting for you to create `main`.
- [x] STEP 7 (code) — Supabase packages installed; browser/server/proxy/admin clients; `src/proxy.ts` refreshes the login session and sends logged-out visitors of protected pages to `/login`; temporary `/health` page; Supabase CLI folder (`supabase/config.toml`). Dev project reference: `ifkkatuluzszzbaebamd` (not secret). Tested here: URL + publishable key accepted; secret key not yet added.
- [x] STEP 8 (written, not applied) — migration `supabase/migrations/20260923065424_foundation.sql` (7 tables, helper functions, triggers, RLS, column grants, indexes) + 51 security tests `supabase/tests/001_foundation.test.sql` + TypeScript types `src/types/database.types.ts`. All 51 tests pass on a practice copy of Supabase's real database here.
- [x] STEP 9 — Login with **Clerk** (D-62): `/login`, `/signup` (email code, forgot password, new-device check), `/auth/continue` (copies name + email from Clerk into `profiles`), `/account-disabled`, header Log in / Sign up / account menu, Supabase client sends the Clerk token. Step 8 migration + 51 tests reworked for Clerk ids (all pass). Tested here with a temporary Clerk test app: Clerk forms load in our design; Supabase accepts real Clerk tokens; user sees only own org, cannot see another org, cannot change own role; forged token refused; profile copy from Clerk works.

## Next step
You: the setup jobs below (Clerk + Supabase), then type "continue" for STEP 10 (onboarding: create an organization, role-based pages).

## Pending actions for you (collected — do them when you are ready)
1. **Security:** delete the Supabase secret keys you pasted in chat and create a new one; reset the database password (Supabase → Project Settings).
2. **GitHub:** ✅ `main` created by Claude (2026-09-23). Still to do by you: make `main` the **default branch** (Settings → General) and in Vercel set Production Branch = `main`, then Redeploy.
3. **Clerk:** create an account + application (clerk.com) → Integrations → **Supabase → Activate** → copy the Clerk domain.
4. **Supabase:** Authentication → Sign In / Providers → **Third-party auth → Clerk** → paste the Clerk domain.
5. **Keys** (never in chat): put `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` + `CLERK_SECRET_KEY` + the Supabase values in `.env.local` and in Vercel → Redeploy.
6. **Database:** `npx supabase login`, `npx supabase link --project-ref ifkkatuluzszzbaebamd`, `npx supabase db push`; then run `supabase/tests/001_foundation.test.sql` in the SQL Editor (expect 51 of 51).
7. **Check:** `npm run dev` → http://localhost:3000/health all green → sign up at http://localhost:3000/signup.

## Open decisions so far
59 of 61 answered. Still open: **D-47** (plans, prices, limits — needed by Step 22) and **D-52** (product name, domain, brand colour — needed by Step 24).
