# 13 — External APIs & Environment Variables

> **API** = a service our software talks to over the internet (e.g. an email-sending service).
> **Environment variable** = a setting (often a secret key) given to the app from outside the code, so secrets never end up in GitHub.

---

## 1. External APIs

Only services that a real V1 feature needs are included.

### 1.1 REQUIRED FOR V1

| Service | Used for | Keys needed | When |
|---|---|---|---|
| **Supabase** (Database, Auth, Storage) | Everything: data, login, files | Project URL, publishable key, secret key | Step 7 |
| **Clerk** (D-62) | Sign-up, login, email verification, password reset, new-device checks, account menu | Publishable key, secret key | Step 9 |
| **Email provider** (D-33: Resend) | Invitation emails from our server (login emails are sent by Clerk) | SMTP credentials (entered in the Supabase dashboard, not in our code) + API key for our server | Supabase built-in email for testing until then; **required before real customers** (Step 24). Invitation emails can start as soon as D-33 is set up (copy-link works before that — D-34) |

### 1.2 OPTIONAL FOR V1

| Service | Used for | Recommendation |
|---|---|---|
| Error monitoring (e.g. Sentry) | Seeing crashes that users hit | **Not in V1** — Vercel's built-in logs are enough at the start (D-54) |
| Separate rate-limit store (e.g. Upstash Redis) | Counting login/invite attempts | **Not needed** — Clerk protects login/sign-up (bot protection, rate limits) and our own limits use a small PostgreSQL table (D-53) |

### 1.3 FUTURE (not V1)

| Service | Possible feature |
|---|---|
| WhatsApp Business Cloud API | Invoice / task notifications on WhatsApp (D-60) |
| SMS gateway (local provider) | OTP or reminders |
| Payment gateway / merchant of record | Automatic subscription payments (D-50); customers paying invoices online |
| AI (e.g. Claude API) | Summaries, drafting messages, smart search |
| Google services | "Log in with Google", Maps for customer addresses, Google Drive import |
| Accounting software (QuickBooks, Xero, local tools) | Export/sync invoices and payments |
| Currency exchange rates | Multi-currency (D-12) |

## 2. Environment variables

### 2.1 List

| Variable | Public or secret | Where used | Required | Notes |
|---|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | **Public** | Browser + server | ✅ | Your Supabase project URL. Safe to be public |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | **Public** | Browser + server | ✅ | The new "publishable" key (starts `sb_publishable_…`). Gives **no** rights by itself; RLS protects the data. Use the legacy `anon` key only if your project does not show a publishable key |
| `NEXT_PUBLIC_SITE_URL` | **Public** | Server (auth redirect links, invitation links) | ✅ local & production | `http://localhost:3000` locally, `https://your-domain` in production. **Leave empty in Preview**: the code then uses Vercel's automatic preview address |
| `SUPABASE_SECRET_KEY` | **SECRET — server only** | Only `src/lib/supabase/admin.ts` (the 2–3 uses in `03-architecture.md` §4.1) | ✅ | The new "secret" key (`sb_secret_…`); legacy `service_role` only if no secret key exists. **Never** `NEXT_PUBLIC_`, never in browser code, never logged |
| `EMAIL_API_KEY` | **SECRET — server only** | Invitation emails (server) | After D-33 | Name may change to match the provider (e.g. `RESEND_API_KEY`) |
| `EMAIL_FROM` | Secret (server only; not sensitive but server-side) | Invitation emails | After D-33 | e.g. `YourApp <no-reply@your-domain>` |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | **Public** | Browser + server (Clerk) | ✅ | Clerk dashboard → API keys (`pk_test_…` / `pk_live_…`) |
| `CLERK_SECRET_KEY` | **SECRET — server only** | Server (Clerk checks, profile copy) | ✅ | Clerk dashboard → API keys (`sk_test_…` / `sk_live_…`). Never `NEXT_PUBLIC_`, never in chat |
| `NEXT_PUBLIC_APP_NAME` | **Public** | Page titles, emails, header | ✅ | Product name (D-52) |

**Not** environment variables of the app:
- **Database password** — only typed into the Supabase CLI on your own computer when needed; never stored in the project.
- **Project reference** — used once with `npx supabase link`; stored by the CLI in its own ignored folder.
- **SMTP password** — entered only in the Supabase dashboard (Authentication → SMTP settings).

### 2.2 Where to set them

| Place | How |
|---|---|
| **Local** | File `.env.local` in the project root. It is listed in `.gitignore`, so it never goes to GitHub. `.env.example` (committed) lists the **names only**, no values |
| **Vercel** | Project → **Settings** → **Environment Variables** → add each name and value → tick the environments (below) → Save → **Redeploy** (variables only apply to new deployments) |

| Variable | Production | Preview | Development (Vercel CLI only) |
|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | prod Supabase project | dev Supabase project | dev |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | prod | dev | dev |
| `SUPABASE_SECRET_KEY` | prod | dev | dev |
| `NEXT_PUBLIC_SITE_URL` | `https://your-domain` | *(leave empty)* | `http://localhost:3000` |
| `EMAIL_API_KEY`, `EMAIL_FROM` | prod values | test values or empty (copy-link only) | test |
| `NEXT_PUBLIC_APP_NAME` | name | name | name |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`, `CLERK_SECRET_KEY` | Clerk **production** instance keys | Clerk development keys | development keys |

Until the production Supabase project exists (Step 24), Production also points to the dev project.

### 2.3 Safety rules (from `CLAUDE.md`)

- Anything starting with `NEXT_PUBLIC_` is copied into the browser code — **only** URL, publishable key, site URL and app name may have this prefix.
- `src/lib/supabase/admin.ts` starts with `import 'server-only'`, so the build fails if a browser component imports it.
- On startup the server checks that required variables exist and shows a clear error ("Missing NEXT_PUBLIC_SUPABASE_URL — see .env.example") instead of a confusing crash. It never prints their values.
- If a secret leaks (e.g. pasted in a chat or committed): rotate it in the Supabase dashboard immediately, update `.env.local` and Vercel, redeploy.

## 3. Dashboard settings that must match

**Clerk dashboard** (menu names may change slightly):

| Setting | Development instance | Production instance |
|---|---|---|
| **Integrations → Supabase → Activate** | ✅ (adds `role: authenticated` to login tokens; shows the **Clerk domain**) | ✅ |
| User & authentication → Email | Email address required + verified; password on | same |
| Password rules | at least 8 characters, letters + numbers (D-35) | same |
| Paths / allowed origins | `http://localhost:3000` | your domain |
| Restrictions → sign-up mode | Public (D-36) | Public |

**Supabase dashboard:**

| Setting | Development project | Production project |
|---|---|---|
| Authentication → Sign In / Providers → **Third-party auth → Add provider → Clerk** | paste the Clerk **development** domain | paste the Clerk **production** domain |
| API settings → **Exposed schemas** | `public` only (never `private`) | same |
| Storage buckets | Created by migrations, not by hand | same |
| Authentication → URL configuration / email templates / SMTP | not used for logins any more (Clerk) | not used |

## 4. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-52 | Product name, domain and brand colour | **STILL OPEN — you decide before Step 24.** Until then `NEXT_PUBLIC_APP_NAME` holds a working name and the default colour is neutral blue. | The name appears in emails, page titles and the domain; not needed to build features. |
| D-53 | How to rate-limit our own actions (invites, resends, uploads) | **Small table in the `private` database schema** that counts attempts per user/IP per time window; Supabase Auth's built-in limits for login/signup/reset. | No extra paid service; enough for V1 traffic. |
| D-54 | Error monitoring service | **Not in V1**; use Vercel logs. Add Sentry when there are paying customers. | Fewer accounts and keys to manage at the start. |

Referenced: D-12, D-33, D-34, D-35, D-50, D-60.
