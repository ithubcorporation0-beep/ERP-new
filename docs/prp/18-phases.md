# 18 — Build Phases

> A **phase** is one small, testable piece of the build. Each phase ends with lint + build passing, a manual test checklist, updated `PROJECT_STATUS.md` / `TODO.md`, a git commit, and a STOP until you say "continue".
> Phase numbers below match the brief (§5, 18-phases). The **Build step** column shows the matching step in `docs/BUILD_ORDER.md`, which is the order we actually follow.

---

## 1. Order and why

| Phase | Build step | Name |
|---|---|---|
| 1 | 5 + 6 | Project setup + GitHub + first Vercel deployment |
| 2 | 7 | Supabase connection + environment variables |
| 3 | 8 | Database foundation |
| 4 | 9 | Authentication |
| 5 | 10 | Onboarding, role routing, app shell |
| 6 | 11 | Invitations & user management |
| 7 | 12 | Customers (+ client linking) |
| 8 | 13 | Projects & tasks |
| 9 | 14 | Services/products catalog |
| 10 | 15 | Invoices + numbering |
| 11 | 16 | Payments |
| 12 | 17 | Expenses |
| 13 | 18 | Documents (storage) |
| 14 | 19 | Notifications |
| 15 | 20 | Dashboards & reports |
| 16 | 21 | Activity log viewer |
| 17 | 22 | Platform admin + plans/subscriptions |
| 18 | 23 | Security audit + RLS test suite |
| 19 | 24 | Production launch |

The recommended order from the brief is kept. It works because each phase only needs earlier ones: people and security first, then customers, work, money, files, and last the cross-cutting parts (notifications, reports, logs), which then have data to show.

**Improvements to the plan (compared with the brief's list):**

1. **Tests grow with every phase, not only in Phase 18.** Each phase that adds tables also adds its pgTAP tests (at least "org A cannot read org B" and the role rules for those tables) and extends `supabase/seed.sql`. Phase 18 then only fills gaps and runs everything together. Reason: security bugs found early are cheaper and less scary to fix.
2. **The audit trigger is attached in the same migration as each new table** (created in Phase 3). Phase 16 only builds the viewer. Reason: no change is ever missed.
3. **Notification hooks:** Phases 6–13 mark the places where notifications will be created with a clear `TODO(notifications)` comment only, never fake code; Phase 14 adds all notification triggers in one migration. (Rule 2 of `CLAUDE.md` forbids incomplete code, so these are comments, not half-written functions.)
4. **Plan limits arrive in Phase 17**, but `private.org_writable()` and `private.org_limits()` exist from Phase 3 (returning "allowed / unlimited"), so all policies already call them and Phase 17 only changes these two functions. Reason: no need to rewrite every policy later.
5. **The rate-limit table is created in Phase 6** (first user: invitations), not in the security audit.
6. **Deploy after every phase**: merge to `main` → Vercel production (still using the dev database until Phase 19).

## 2. Phase details

Every phase also has these standard rules (not repeated below): migrations explained in plain English and approved by you before applying; RLS + policies + indexes + audit trigger in the same migration; Zod on every action; `npm run lint` + `npm run build` pass; `PROJECT_STATUS.md`, `TODO.md`, `DECISIONS.md` updated; git commit.

---

### Phase 1 — Project setup + GitHub + first deployment (Steps 5–6)

| | |
|---|---|
| Objective | A running Next.js app, stored on GitHub and live on Vercel |
| Files / modules | `package.json`, `next.config.ts`, `tsconfig.json`, `components.json`, `eslint.config.mjs`, `.gitignore`, `.env.example`, `README.md`, `src/app/layout.tsx`, `src/app/globals.css`, `src/app/(public)/page.tsx`, `src/components/ui/*` (first shadcn components) |
| Dependencies | Decisions D-52 (working name is enough) |
| Deliverables | Next.js (TypeScript, App Router, Tailwind, ESLint, `src/`) created **in the existing folder without touching `CLAUDE.md` and `docs/`**; shadcn/ui initialised; simple home page; `.gitignore` includes `.env*.local`; first commit; pushed to GitHub; first Vercel deployment |
| ACTION REQUIRED FROM ME | Create an empty GitHub repository (or confirm the existing one); import it in Vercel (Add New → Project → Import → Deploy) |
| Test checklist | `npm run dev` → http://localhost:3000 shows the home page; the `.vercel.app` link shows the same page; a push to a branch creates a Preview link |
| Definition of done | Home page live on Vercel from `main`; lint and build clean |

### Phase 2 — Supabase connection + environment variables (Step 7)

| | |
|---|---|
| Objective | The app can talk to Supabase safely |
| Files / modules | `.env.local`, `.env.example`, `src/lib/env.ts`, `src/lib/supabase/{client,server,proxy,admin}.ts`, `src/proxy.ts` (or `middleware.ts`), `src/app/health/page.tsx`, `supabase/config.toml` |
| Dependencies | Phase 1; D-56, D-57 (region) |
| Deliverables | Packages `@supabase/ssr`, `@supabase/supabase-js`, `server-only`, CLI via `npx supabase`; browser/server/proxy clients per the official docs **for the installed versions**; admin client marked server-only; env check with clear messages; `/health` page shows "Supabase connected" or a clear error; CLI linked to the dev project |
| ACTION REQUIRED FROM ME | Create Supabase project `saas-app-dev` (region D-57), save DB password privately; paste URL + publishable key + secret key into `.env.local` yourself (never into the chat); run `npx supabase login` and `npx supabase link`; add the same variables in Vercel (Preview + Production) and Redeploy |
| Test checklist | `/health` locally → connected; on Vercel → connected; searching the built browser files for the secret key finds nothing |
| Definition of done | Connected locally and on Vercel; no secret in git or browser code |

### Phase 3 — Database foundation (Step 8)

| | |
|---|---|
| Objective | The secure base every other table builds on |
| Files / modules | `supabase/migrations/*_foundation.sql`, `supabase/tests/foundation.test.sql`, `supabase/seed.sql`, `src/types/database.types.ts` |
| Dependencies | Phase 2; decisions in group A of `19-decisions-required.md` answered |
| Deliverables | Tables `organizations`, `organization_settings`, `profiles`, `memberships`, `invitations`, `platform_admins`, `activity_logs`; `private` schema with helper functions (`is_member`, `has_role`, `my_role`, `my_membership_id`, `is_platform_admin`, `org_writable`, `can_write`, `org_limits`); shared triggers (`set_updated_at`, `force_created_by`, `prevent_org_change`, `handle_new_user`, `audit_row_change`, memberships owner/self-change protection); RLS + policies + column grants + indexes; pgTAP tests; seed with two organizations; generated TypeScript types |
| ACTION REQUIRED FROM ME | Read the plain-English migration summary and say OK; run the test command given |
| Test checklist | Tests pass: org A cannot read org B's organization/memberships/invitations/logs; user cannot change own role; only one OWNER per org; `anon` sees nothing; logs cannot be updated/deleted; a new signup gets a profile |
| Definition of done | Migration applied to dev; all foundation tests pass; types generated |

### Phase 4 — Authentication (Step 9)

| | |
|---|---|
| Objective | People can sign up, verify, log in, log out and reset passwords |
| Files / modules | `src/app/(auth)/*`, `src/app/auth/confirm/route.ts`, `src/app/auth/signout/route.ts`, `src/app/(account)/account-disabled`, `src/features/auth/*`, `src/lib/auth/*` |
| Dependencies | Phase 3; D-35, D-36 |
| Deliverables | Pages `/signup`, `/login`, `/forgot-password`, `/reset-password`, `/verify-email`, `/account-disabled`; email confirmation route; logout; `zod`, `react-hook-form`, `@hookform/resolvers`, `sonner`; protection of `/app`, `/platform`, account pages; safe `next` redirects |
| ACTION REQUIRED FROM ME | Supabase → Authentication → URL Configuration (Site URL + Redirect URLs); edit email templates (exact text given); check "Confirm email" is on |
| Test checklist | Sign up → email → confirm → logged in; wrong password → generic error; forgot password → email → new password works; `/app/x` while logged out → login; logout works; note the built-in email hourly limit |
| Definition of done | All auth flows work locally and on the Preview link |

### Phase 5 — Onboarding, role routing, app shell (Step 10)

| | |
|---|---|
| Objective | A new user creates an organization and lands in the right panel |
| Files / modules | `src/app/(account)/{onboarding,select-organization,organization-suspended}`, `src/app/app/[orgSlug]/{layout,page,loading,error,profile,settings}`, `src/app/platform/{layout,page}`, `src/components/layout/*`, `src/lib/auth/{require-membership,resolve-home-path}.ts`, `src/lib/permissions.ts`, migration with `create_organization`, `get_my_organizations`, `change_organization_currency` |
| Dependencies | Phase 4; D-12, D-37 |
| Deliverables | Onboarding form with slug check; home-path logic (`05-auth-onboarding.md` §8); app shell (sidebar per role, header with logo/name, org switcher, user menu, mobile drawer); empty dashboard per role; "No access" and "Not found" pages; organization settings page (basic); `/platform` shell; safe SQL to make your account PLATFORM_ADMIN |
| ACTION REQUIRED FROM ME | Run the given SQL in the Supabase SQL Editor to make your own account platform admin |
| Test checklist | New user → onboarding → OWNER dashboard; slug taken → error; typing another org's slug → "No access"; phone width → drawer menu; platform admin → `/platform` |
| Definition of done | Every route under `/app/[orgSlug]` and `/platform` is protected on the server |

### Phase 6 — Invitations & user management (Step 11)

| | |
|---|---|
| Objective | OWNER/ADMIN manage the team |
| Files / modules | `src/app/app/[orgSlug]/team/*`, `src/app/invite/[token]`, `src/features/members/*`, migration with `get_invitation_preview`, `accept_invitation`, `change_member_role`, `set_member_status`, `transfer_ownership`, `leave_organization`, `private.rate_limits` |
| Dependencies | Phase 5; D-09, D-23, D-34, D-46 (email sending needs D-33 — copy-link works without it) |
| Deliverables | Invite (roles except OWNER; CLIENT completed in Phase 7), copy link, resend, cancel, accept flow, change role, disable/enable, transfer ownership, leave; limits on invites/resends; everything logged |
| ACTION REQUIRED FROM ME | Test with a second email address in an incognito window |
| Test checklist | Invite → accept with the right email works; wrong email refused; expired/cancelled link refused; ADMIN cannot change OWNER; nobody changes own role; disabled member loses access immediately; ownership transfer swaps roles |
| Definition of done | pgTAP tests for these functions pass |

### Phase 7 — Customers + client linking (Step 12)

| | |
|---|---|
| Objective | Customer list and client logins |
| Files / modules | `src/app/app/[orgSlug]/customers/*`, `src/features/customers/*`, migration `customers` + `customer_id` composite FKs on `memberships`/`invitations` + `client_customer_id()` |
| Dependencies | Phase 6; D-05, D-08, D-16, D-29 |
| Deliverables | List (search, filters, pagination), create, edit, archive/restore, detail with tabs (filled as modules arrive), invite client login; client dashboard shows own customer |
| Test checklist | Client A cannot see customer B (UI and pgTAP); employee sees nothing yet (no projects); accountant can create but not archive |
| Definition of done | RLS tests pass; CLIENT invite flow complete |

### Phase 8 — Projects & tasks (Step 13)

| | |
|---|---|
| Objective | Plan and track work |
| Files / modules | `src/app/app/[orgSlug]/{projects,tasks}/*`, `src/features/{projects,tasks}/*`, migration `projects`, `project_members`, `tasks`, `task_comments`, `is_project_member()`, `clients_see_tasks()` |
| Dependencies | Phase 7; D-03, D-06, D-07, D-17 |
| Deliverables | Project CRUD + members; task CRUD, assignment (auto-adds to project), status changes, comments; employee "My Tasks/My Projects"; client "My Projects" (+ tasks if setting on); `TODO(notifications)` markers |
| Test checklist | Employee sees only assigned tasks and can change only status; client sees only own projects; accountant view-only; archive/restore |
| Definition of done | RLS tests pass for all four tables |

### Phase 9 — Services/products catalog (Step 14)

| | |
|---|---|
| Objective | Price list |
| Files / modules | `src/app/app/[orgSlug]/services/*`, `src/features/catalog/*`, migration `services_products` |
| Dependencies | Phase 5; D-10, D-19 |
| Deliverables | CRUD + archive, type filter, SKU uniqueness |
| Test checklist | Manager view-only; employee/client no access; duplicate SKU refused |
| Definition of done | RLS tests pass |

### Phase 10 — Invoices + numbering (Step 15)

| | |
|---|---|
| Objective | Create, issue and print invoices with safe numbers |
| Files / modules | `src/app/app/[orgSlug]/invoices/*`, `src/app/app/[orgSlug]/settings/invoices`, `src/features/invoices/*`, migration `invoices`, `invoice_items`, `number_sequences`, `recalc_invoice_totals`, `issue_invoice`, `void_invoice`, `duplicate_invoice`; `vitest` |
| Dependencies | Phases 7–9; D-10, D-11, D-12, D-13, D-31, D-40, D-42 |
| Deliverables | Draft editor with lines, database totals, issue, void, duplicate, print view (DRAFT/VOID watermarks), invoice settings, client "My Invoices", computed overdue |
| Test checklist | Totals correct (worked example in `09-finance.md`); parallel issue gives different numbers; issued invoice cannot be edited; client never sees drafts; browser-sent totals ignored |
| Definition of done | Money unit tests + pgTAP tests pass |

### Phase 11 — Payments (Step 16)

| | |
|---|---|
| Objective | Record and reverse payments safely |
| Files / modules | `src/app/app/[orgSlug]/payments/*`, `src/features/payments/*`, migration `payments`, `record_payment`, `reverse_payment`, `apply_payment_to_invoice` |
| Dependencies | Phase 10; D-14, D-15, D-32 |
| Deliverables | Record from invoice, payment list/detail, receipt view, reversal with reason, statuses update automatically |
| Test checklist | Partial → partially paid; full → paid; overpayment refused; reversal restores balance; payment cannot be deleted; void invoice with payments refused |
| Definition of done | Tests pass |

### Phase 12 — Expenses (Step 17)

| | |
|---|---|
| Objective | Record spending |
| Files / modules | `src/app/app/[orgSlug]/expenses/*`, `src/features/expenses/*`, migration `expense_categories` (+ starter categories for existing organizations, and `create_organization` updated), `expenses`, `void_expense` |
| Dependencies | Phase 8 (optional project link); D-20 |
| Deliverables | Expense CRUD + void, categories page, filters |
| Test checklist | Manager/employee/client no access; void excluded from totals |
| Definition of done | Tests pass |

### Phase 13 — Documents (Step 18)

| | |
|---|---|
| Objective | Files attached to records, private and safe |
| Files / modules | `src/features/documents/*`, `src/components/shared/file-upload.tsx`, `src/app/app/[orgSlug]/documents/*`, migration `documents` + buckets `org-files`, `org-logos` + storage policies |
| Dependencies | Phases 7–12; D-21, D-22, D-43, D-44 |
| Deliverables | Prepare/confirm upload flow, signed download URLs, visible-to-client switch, delete rules, organization logo upload, documents page, orphan clean-up script |
| Test checklist | All tests in `10-documents.md` §10 |
| Definition of done | Storage + RLS tests pass |

### Phase 14 — Notifications (Step 19)

| | |
|---|---|
| Objective | In-app bell |
| Files / modules | `src/features/notifications/*`, header bell, `src/app/app/[orgSlug]/notifications`, migration `notifications`, `private.notify`, triggers for every event in `11-notifications-audit.md` §1.2, pg_cron clean-up |
| Dependencies | Phases 6–13; D-27, D-30, D-60 |
| Deliverables | Bell with unread count, dropdown, page, mark read / all read, all `TODO(notifications)` markers replaced, announcement banner (when Phase 17 adds announcements it plugs in here) |
| Test checklist | Assign a task → assignee sees it (not the manager who assigned); client gets invoice-issued; nobody reads another person's notifications |
| Definition of done | No `TODO(notifications)` left |

### Phase 15 — Dashboards & reports (Step 20)

| | |
|---|---|
| Objective | Numbers that help run the business |
| Files / modules | `src/app/app/[orgSlug]/page.tsx` (per role), `src/app/app/[orgSlug]/reports/*`, `src/features/reports/*`, migration with report functions/views; `recharts` |
| Dependencies | Phases 7–12; D-41, D-55 |
| Deliverables | Dashboard per role, work and financial reports with date filters, aging, customer statement, CSV export (if D-55 yes) |
| Test checklist | Numbers match manual sums on seed data; manager cannot open financial reports; CSV opens correctly in Excel |
| Definition of done | All calculations in the database; no page loads whole tables |

### Phase 16 — Activity log viewer (Step 21)

| | |
|---|---|
| Objective | OWNER/ADMIN can see who changed what |
| Files / modules | `src/app/app/[orgSlug]/activity/*`, `src/features/activity/*` |
| Dependencies | All earlier phases |
| Deliverables | Log list with filters, detail drawer (old → new); check that every PRP table has the audit trigger and that no secret columns are logged |
| Test checklist | Change an invoice draft → entry shows the changed field; other roles have no access; entries cannot be edited |
| Definition of done | Audit coverage query returns every business table |

### Phase 17 — Platform admin + plans/subscriptions (Step 22)

| | |
|---|---|
| Objective | Run the SaaS: organizations, plans, manual billing |
| Files / modules | `src/app/platform/*`, `src/app/app/[orgSlug]/billing`, `src/app/(public)/pricing`, `src/features/platform/*`, migration `plans`, `subscriptions`, `subscription_payments`, `platform_settings`, `platform_announcements`, real `org_writable()` / `org_limits()`, trial rows for existing organizations |
| Dependencies | Phases 5–16; D-24, D-25, D-28, D-47, D-48, D-49 |
| Deliverables | Organizations list/detail, suspend/activate, plans CRUD, record payment & extend, announcements, platform settings, user disable/enable, billing page, read-only mode, limits enforced |
| ACTION REQUIRED FROM ME | Provide plan names/prices/limits (D-47) and billing instructions text |
| Test checklist | Expired trial → read-only everywhere; suspend → suspended page; limit reached → friendly message; platform admin cannot see tenant business data (D-01) |
| Definition of done | Tests pass |

### Phase 18 — Security audit + full test suite (Step 23)

| | |
|---|---|
| Objective | Prove the system is safe before real customers |
| Files / modules | Whole project; `next.config.ts` (headers); `tests/e2e/*` (D-61) |
| Dependencies | Phases 1–17; D-53, D-54, D-61 |
| Deliverables | Every item S-01…S-23 in `16-security-performance-testing.md` reported as PASSED / FIXED / NEEDS MY DECISION; security headers; rate limits reviewed; `npm audit`; Supabase Security & Performance Advisors clean; full role matrix test run |
| Test checklist | All automated tests green; role matrix (§3.3 of file 16) checked manually |
| Definition of done | Every item is PASSED or FIXED, or you have answered it in writing |

### Phase 19 — Production launch (Step 24)

| | |
|---|---|
| Objective | Real customers can use it |
| Files / modules | Configuration only (no new features) |
| Dependencies | Phase 18; D-33, D-52, D-56, D-57, D-58 |
| Deliverables | Launch checklist in `17-deployment.md` §8 completed, every production command confirmed with you first |
| ACTION REQUIRED FROM ME | Create production Supabase project (Pro plan), Vercel Pro, domain, email provider + domain verification, production env variables, Auth URL settings, backups |
| Test checklist | Smoke test on the live site: signup → onboarding → invite → customer → project → task → invoice → payment → client view; password reset email arrives; backup restore tested |
| Definition of done | Live on your domain, first real organization can sign up |
