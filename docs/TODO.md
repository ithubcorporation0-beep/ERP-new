# TODO

## Stage 1 — The plan
- [x] STEP 1 — PRP batch A (01–04)
- [x] STEP 2 — PRP batch B (05–10)
- [x] STEP 3 — PRP batch C (11–17)
- [x] STEP 4 — Phases + decisions (18–19) written, consistency review done
- [x] STEP 4 — Decisions answered; PRP updated; DECISIONS.md filled

## Open decisions
- [ ] D-47 — plan names, prices, limits (before Step 22)
- [ ] D-52 — product name, domain, brand colour (before Step 24; working name is fine until then)

## Stage 2 — Setup
- [x] STEP 5 — Project setup (app created, lint + build pass)
- [ ] STEP 5 — GitHub: create `main` branch and make it the default (you)
- [ ] STEP 6 — First Vercel deployment (instructions given; waiting for you: import in Vercel, Deploy, send the .vercel.app link)
- [x] STEP 7 — Connect Supabase: code done
- [ ] STEP 7 — You: secret key in .env.local + Vercel variables + Redeploy; `npx supabase login` + `npx supabase link`; /health shows ✅

## Stage 3 — Foundation
- [x] STEP 8 — Database foundation: migration + tests + types written and tested locally
- [ ] STEP 8 — You: OK the migration, `npx supabase db push`, run tests in SQL Editor (expect 51 of 51)
- [ ] Seed data (two demo organizations with real logins) — moved to Step 10, when login pages exist
- [ ] `private.org_limits()` — moved to Step 11 (its first user: invitations)
- [ ] STEP 9 — Authentication
- [ ] STEP 10 — Onboarding, role routing, app shell
- [ ] STEP 11 — Invitations & user management

## Stage 4 — Business modules
- [ ] STEP 12 — Customers + client login link
- [ ] STEP 13 — Projects & tasks
- [ ] STEP 14 — Services/products catalog
- [ ] STEP 15 — Invoices
- [ ] STEP 16 — Payments
- [ ] STEP 17 — Expenses + categories
- [ ] STEP 18 — Documents
- [ ] STEP 19 — In-app notifications
- [ ] STEP 20 — Dashboards & reports
- [ ] STEP 21 — Activity log viewer

## Stage 5 — SaaS, security, launch
- [ ] STEP 22 — Platform admin + plans/subscriptions
- [ ] STEP 23 — Security audit
- [ ] STEP 24 — Production launch
