# 17 — Deployment

> **Deployment** = putting the software on the internet so people can use it.
> **GitHub** stores the code. **Vercel** builds the website from GitHub and runs it. **Supabase** runs the database, login and files.

---

## 1. The flow

```
Your computer ──git push──► GitHub ──automatic──► Vercel builds ──► Website live
                                                      │
                                         reads env variables (Vercel settings)
                                                      │
                                                      ▼
                                                 Supabase project
```

- Every push to the **`main` branch** → Vercel builds a **Production** deployment → the real website updates (usually in 1–3 minutes).
- Every push to **any other branch** (and every pull request) → a **Preview** deployment with its own temporary link (`something-git-branch-yourteam.vercel.app`). Perfect for testing a step before it goes live.
- If a build fails, Vercel keeps the previous working version online and shows the error in the Deployments list.
- **Rollback**: in Vercel → Deployments → pick an older working deployment → "Promote to Production" (instant; database changes are **not** rolled back — see §4).
- We deploy **early** (Step 6) and after every step, not only at the end, so problems are found while they are small.

## 2. Environments

| Environment | Website | Supabase project | Who uses it |
|---|---|---|---|
| Local | `http://localhost:3000` (`npm run dev`) | `saas-app-dev` | You while building |
| Preview | Vercel preview links | `saas-app-dev` | Testing each branch |
| Production | Your domain (until then `your-app.vercel.app`) | `saas-app-prod` (from Step 24; until then dev) | Real customers |

**D-56 — separate Supabase projects for development and production: YES.** Test data, test users and experimental migrations never touch real customers' data, and a mistake in development cannot delete production data.

Environment variables per environment: `13-apis-env.md` §2.2. Supabase Auth URL settings per project: `13-apis-env.md` §3.

**D-57 — region:** the Supabase region **closest to Pakistan** that is offered when creating the project (at the time of writing that is **Mumbai / `ap-south-1`**; verify in the dropdown), and Vercel Functions set to the matching region (**Mumbai, `bom1`**) in Vercel → Project → Settings → Functions. Same region = fast database calls.

## 3. Branches and releases

- `main` = production. Work happens on step branches (e.g. `step-12-customers`), tested on the Preview link, then merged into `main`.
- Never `git push --force` to `main` (rule 7 in `CLAUDE.md`).
- Each merge to `main` should include: passing `npm run lint`, `npm run build`, tests, updated `PROJECT_STATUS.md`/`TODO.md`.

## 4. Database migrations

- Every database change is a file in `supabase/migrations/` (created with `npx supabase migration new <name>`), committed to git.
- **Development**: applied to `saas-app-dev` with `npx supabase db push` (after the plain-English explanation and your OK).
- **Production** (from Step 24): Claude **always asks you first**, then:
  1. make sure a fresh backup exists (§6),
  2. `npx supabase link --project-ref <prod-ref>` (prod project),
  3. `npx supabase db push --dry-run` → shows which migrations will run,
  4. `npx supabase db push` → applies them,
  5. link back to the dev project.
- **Order**: apply the migration to production **before** merging code that needs it (new code expects the new tables). Migrations are written to be **additive** (add tables/columns first, remove old ones in a later migration), so old and new code both work during the switch.
- A migration already applied is never edited; fixes are new migrations.
- `seed.sql` is **never** run on production.

## 5. Custom domain

1. Buy a domain (D-52) from any registrar.
2. Vercel → Project → **Settings → Domains** → Add `yourdomain.com` (and `www.yourdomain.com`, redirected to one of them).
3. Vercel shows DNS records (an `A` record and/or `CNAME`) → add them at your registrar → wait until Vercel shows "Valid" (minutes to a few hours). HTTPS certificates are automatic.
4. Update `NEXT_PUBLIC_SITE_URL` in Vercel Production, Supabase prod **Site URL** and **Redirect URLs**, then redeploy.
5. Email (D-33): verify the domain in the email provider (it gives DNS records: SPF, DKIM, DMARC) so emails don't land in spam.
6. Subdomains per organization: not in V1 (D-04).

## 6. Backups

- **Supabase Pro** includes automatic daily backups kept for 7 days (restorable from the dashboard). Point-in-time recovery (restore to any minute) is a paid add-on — later if needed.
- **Decided (D-58):** Pro daily backups **plus** a monthly manual export (`npx supabase db dump` of the production database, stored safely off-line, encrypted), and a copy of Storage files for important customers when needed.
- The free plan should not be relied on for backups (check current Supabase plan details).
- **Test a restore** once before launch (restore a backup into a spare project and open it).
- Code is backed up by GitHub.

## 7. Plan limits — honest notes

- **Vercel Hobby (free) is for personal, non-commercial use only.** A SaaS that charges customers must use **Vercel Pro** (paid per team member per month — check the current price).
- **Supabase Free projects pause after about a week without activity** and have tighter limits (database size, storage, email). A paused project means the website stops working until you un-pause it. Real customers need **Supabase Pro** (paid per month per organization, plus usage — check the current price).
- Free plans are fine for Steps 5–23 (building and testing). **Upgrade both before the first real customer** (Step 24).
- Supabase built-in email is for testing only; production needs custom SMTP (D-33).

## 8. Launch checklist (summary — full version in Step 24)

1. Production Supabase project created (region D-57), Pro plan.
2. All migrations applied to production; `seed.sql` not applied.
3. Storage buckets exist (created by migrations); check policies in the dashboard.
4. Auth: Site URL + Redirect URLs for the real domain; email templates; custom SMTP; confirm email on; password rules; rate limits reviewed.
5. Vercel Production env variables point to the prod project; Vercel Pro; function region set.
6. Custom domain + HTTPS; email domain verified.
7. Your platform admin account created in prod (safe SQL given in Step 10).
8. Plans created (D-47), billing instructions filled, trial length set (D-48).
9. `/health` page removed; Supabase Security & Performance Advisors show no errors.
10. Backup taken and a restore tested.
11. Smoke test on the live site (signup → onboarding → invite → customer → project → task → invoice → payment → client view).

## 9. Monitoring after launch

- Vercel → Logs / Observability for server errors.
- Supabase → Logs (API, Auth, Database) and Reports (usage).
- Supabase usage emails (approaching limits).
- Error monitoring service later (D-54).

## 10. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-56 | Separate Supabase projects for development and production | **Yes** (`saas-app-dev` and `saas-app-prod`). | Test data and mistakes never touch real customers. |
| D-57 | Hosting region | **Supabase Mumbai (`ap-south-1`) + Vercel Functions Mumbai (`bom1`)** — verify availability. | Closest to users in Pakistan; same region keeps the app fast. |
| D-58 | Backups | **Supabase Pro daily backups + monthly manual export**, restore tested before launch. | Protection against mistakes and provider problems at low cost. |

Referenced: D-04, D-33, D-47, D-48, D-52, D-54.
