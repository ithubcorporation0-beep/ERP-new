# BUILD ORDER

Every step ends with: run `npm run lint` + `npm run build` (from Step 5 onwards), update PROJECT_STATUS.md and TODO.md, git commit, give me a numbered manual test checklist, then STOP.
Whenever I must do something myself, write a block titled **ACTION REQUIRED FROM ME** with exact clicks and values. I use Windows and PowerShell.

---------------- STAGE 1: THE PLAN (no code yet) ----------------

STEP 1 — PRP batch A
Write docs/prp/01-overview.md, 02-roles-permissions.md, 03-architecture.md, 04-database.md following PART B section 5. Unknowns = [DECISION REQUIRED] + your recommended default. Summarize each file in simple English. STOP.

STEP 2 — PRP batch B
Write 05-auth-onboarding.md, 06-authorization-rls.md, 07-panels.md, 08-workflows.md, 09-finance.md, 10-documents.md. Consistent with batch A. Summarize. STOP.

STEP 3 — PRP batch C
Write 11-notifications-audit.md, 12-billing-subscriptions.md, 13-apis-env.md, 14-ui-ux.md, 15-folder-structure.md, 16-security-performance-testing.md, 17-deployment.md. Summarize. STOP.

STEP 4 — Phases + decisions
Write 18-phases.md and 19-decisions-required.md. Re-read all PRP files and fix inconsistencies (list what you fixed). Show me the decisions grouped: "blocks database" / "blocks later phase" / "can wait", each with your recommendation. STOP and wait for my answers.
When I answer (I may say "use your recommendation" for any), update all PRP files, remove answered [DECISION REQUIRED] marks, record them in docs/DECISIONS.md. STOP.

---------------- STAGE 2: SETUP ----------------

STEP 5 — Project setup + GitHub
Create the Next.js app IN THIS FOLDER (TypeScript, App Router, Tailwind, ESLint, src/), without deleting CLAUDE.md or docs/. Add shadcn/ui. Create only the folders needed now from 15-folder-structure.md. Create .gitignore (must include .env*.local), .env.example (names only, no values), simple home page. Init git, first commit.
ACTION REQUIRED FROM ME: exact steps to create an empty GitHub repo (no README), then you run the push commands.
Test: `npm run dev` → http://localhost:3000. STOP.

STEP 6 — First Vercel deployment (deploy early)
Give me ACTION REQUIRED steps: vercel.com → Add New → Project → Import my repo → Next.js detected → Deploy → open the .vercel.app link. Explain that every push to main updates the live site and other branches create Preview links. STOP.

STEP 7 — Connect Supabase
ACTION REQUIRED FROM ME first: create Supabase project `saas-app-dev` (save DB password, region closest to Pakistan), find Project URL, publishable key, secret key, project reference. I will NOT paste keys into this chat.
You: create .env.local with empty variables and tell me where to paste each value; install @supabase/ssr and @supabase/supabase-js; create browser, server and proxy/middleware clients per the official @supabase/ssr docs for the installed Next.js version; server-only admin client (secret key, cannot be imported in client code); set up Supabase CLI with npx and give me the login + link commands; temporary /health page showing "Supabase connected" or a clear error.
ACTION REQUIRED FROM ME after: add the same env variables in Vercel → Settings → Environment Variables, then Redeploy. STOP.

---------------- STAGE 3: FOUNDATION ----------------

STEP 8 — Database foundation
Foundation tables only (organizations, profiles, memberships, invitations, platform_admins, organization_settings, activity_logs + anything the PRP requires for them). Helper functions (is_member, has_role, is_platform_admin, …) with security definer + fixed search_path, RLS + policies on every table, indexes, updated_at triggers, profile-on-signup trigger, base audit trigger. Explain the migration in simple words BEFORE applying and ask me. Create SQL tenant-isolation tests (org A cannot read org B; user cannot change own role) and tell me how to run them. Generate TypeScript types. STOP.

STEP 9 — Authentication
ACTION REQUIRED FROM ME first: Supabase → Authentication → URL Configuration: Site URL http://localhost:3000; Redirect URLs http://localhost:3000/** and https://MY-APP.vercel.app/**.
Build /signup, /login, logout, /forgot-password, /reset-password, email verification callback, account-disabled page. shadcn forms, Zod on server, clear errors, loading states. Protect /app and /platform. Warn me that Supabase built-in email only sends a few emails per hour. STOP.

STEP 10 — Onboarding, role routing, app shell
/onboarding (create organization → user becomes OWNER), /select-organization, login redirect logic from PART B section 1.3, organization-suspended page. App shell under /app/[orgSlug]: sidebar + header (org name/logo, user menu, org switcher), different menu per role, empty dashboard per role, mobile drawer. Server-side membership + role check on EVERY page ("no access" for other org slugs or forbidden pages). /platform shell for PLATFORM_ADMIN; give me safe SQL to make my own account platform admin. STOP.

STEP 11 — Invitations & user management
Invite by email with role (CLIENT needs a customer — finish in Step 12), resend, cancel, change role, disable member, transfer ownership (Owner only). Nobody changes their own role; Admin cannot touch Owner; invites expire. Log everything. Tell me to test with a second email in an incognito window. STOP.

---------------- STAGE 4: BUSINESS MODULES ----------------
(For every module: migration first, explained in simple words, ask before applying; RLS + server checks + Zod; search, filters, pagination.)

STEP 12 — Customers + client login link. RLS test: client A cannot see customer B. STOP.
STEP 13 — Projects & tasks. Admin/Manager full CRUD + assignment; Employee only assigned items; Client only own customer's projects. Leave notification hooks as TODO (no fake code). RLS tests. STOP.
STEP 14 — Services/products catalog. STOP.
STEP 15 — Invoices. Per-organization numbering that never duplicates; totals calculated on server/database; statuses and edit rules from PRP; printable view; client sees only own invoices; automated tests for money calculations. STOP.
STEP 16 — Payments. Updates amount paid / balance / status safely; overpayment and reversal rules from PRP; tests. STOP.
STEP 17 — Expenses + categories (receipt upload comes in Step 18). STOP.
STEP 18 — Documents. Private buckets + storage policies in a migration; path starts with organization_id; server-checked size/type limits; signed URLs only; attach to customers/projects/invoices/expenses; organization logo. Tests: org A cannot download org B's file; client cannot download another client's file. STOP.
STEP 19 — In-app notifications. Bell, unread count, mark read / all read; fill earlier TODO hooks. No email/WhatsApp unless PRP says V1. STOP.
STEP 20 — Dashboards & reports per role, date filters, database-side calculations (never load whole tables), CSV export if in PRP. STOP.
STEP 21 — Activity log viewer (Owner/Admin), filters, pagination; confirm audit triggers cover every PRP table and no secrets are logged. STOP.

---------------- STAGE 5: SaaS, SECURITY, LAUNCH ----------------

STEP 22 — Platform admin + plans/subscriptions. Organizations list, suspend/activate, plans, manual activation/extension of subscriptions with a note (manual billing V1), announcements, server-side plan limits, trial/expiry behavior from PRP. STOP.

STEP 23 — Security audit. Using 16-security-performance-testing.md: RLS on every table, no secrets in client code or NEXT_PUBLIC_ vars, every server action validates + checks role, tenant isolation tests, storage policies, rate limiting on login/signup/invites, security headers, safe error pages. Run all tests. Report PASSED / FIXED / NEEDS MY DECISION; fix one at a time with explanation. STOP.

STEP 24 — Production launch. ACTION REQUIRED checklist: separate production Supabase project, apply migrations there, production env vars in Vercel, Auth URL settings for real domain, custom SMTP for emails, custom domain on Vercel, backups, upgrade to Vercel Pro + Supabase Pro before real customers (Hobby is non-commercial; free Supabase pauses when inactive). Ask me before every production command. Then give me a smoke-test checklist for the live site. STOP.

---------------- ALWAYS ----------------
- If I paste an error: diagnose first, explain the cause simply, fix only what's needed.
- If I ask for a change: first tell me which PRP files, tables and pages it affects and whether a migration is needed; wait for my OK.
- If I say "explain": explain like I'm new to web development, short.
