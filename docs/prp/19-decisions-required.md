# 19 — Decisions Required

> Every question raised in the PRP, numbered D-01 … D-61, with the options and the chosen answer.
> **Status (2026-09-23):** you answered "yes" = **use the recommendation for all**. 59 decisions are answered; **2 are still open: D-47 (plans & prices, needed by Step 22) and D-52 (product name/domain/colour, needed by Step 24)**.
> All PRP files were updated to match, and every answer is recorded in `docs/DECISIONS.md`. To change an answer later, say so — Claude will first list which files, tables and pages it affects.

Groups:
- **A. Blocks the database** — changes table design or security rules; needed before Step 8 (foundation) or before the step that creates those tables.
- **B. Blocks a later phase** — needed before a specific later step.
- **C. Can wait** — V2 topics or settings that can change anytime.

"Needed by" = the build step (`docs/BUILD_ORDER.md`) that uses it. "File" = where it is explained.

---

## A. Blocks the database

| # | Question | Options | Chosen (2026-09-23) | Needed by | File |
|---|---|---|---|---|---|
| D-01 | Can PLATFORM_ADMIN read an organization's business data (support)? | a) never · b) read-only, every view logged · c) only with the OWNER's time-limited permission | **a) Never in V1** (c later) | Step 8 | 02 |
| D-06 | Can CLIENTs see tasks? | a) never · b) organization setting, off by default · c) always | **b) Setting, off by default**; title/status/due date only | Step 8 (settings column), 13 | 02 |
| D-10 | Tax model | a) no tax at all · b) optional tax % per line + org default rate + label · c) one tax % per invoice | **b)**, default 0%, no tax law assumed | Step 14–15 | 04, 09 |
| D-11 | Discount model | a) amount per line · b) % per line · c) one discount on the whole invoice | **a) Amount per line**, tax after discount | Step 15 | 04, 09 |
| D-12 | Currency | a) one per organization, locked after first invoice · b) per invoice (multi-currency) | **a)**, default PKR | Step 8 | 04, 09 |
| D-13 | Invoice number format | a) `INV-2026-0001`, yearly restart, given at issue · b) never restarts `INV-000001` · c) given when draft is created | **a)** with editable prefix | Step 15 | 04, 09 |
| D-14 | Payment rules | a) one invoice per payment, no overpayment, no advances · b) allow overpayment as customer credit · c) one payment split over many invoices | **a) in V1** | Step 16 | 04, 09 |
| D-15 | Payment methods | a) fixed list (cash, bank transfer, JazzCash, Easypaisa, cheque, card, other) · b) each organization edits its own list | **a) Fixed list** + reference field | Step 16 | 04, 09 |
| D-16 | Several contact people per customer? | a) one contact on the customer · b) separate contacts table | **a) in V1** | Step 12 | 04 |
| D-17 | Internal projects (no customer) and tasks without a project? | a) both allowed · b) customer and project always required | **a) Both allowed** | Step 13 | 04 |
| D-18 | Project budget field | a) not in V1 · b) in a separate finance-only table now | **a) Not in V1** | Step 13 | 04 |
| D-19 | Stock / inventory for products | a) no · b) simple stock quantity | **a) No** | Step 14 | 04 |
| D-24 | How an organization is deleted | a) OWNER request → hidden → permanently deleted by PLATFORM_ADMIN after 30 days · b) immediate deletion · c) never deleted | **a)** | Step 8 (status value), 22 | 02, 04 |
| D-29 | One client login linked to several customers? | a) one customer per client login · b) several | **a) One** | Step 12 | 02 |
| D-31 | Can an issued invoice be edited? | a) no — void + duplicate · b) yes while unpaid, with log · c) yes, always | **a) No** | Step 15 | 04, 09 |
| D-32 | Can a payment be deleted? | a) no — reverse only · b) OWNER may delete | **a) Reverse only** | Step 16 | 04, 09 |

## B. Blocks a later phase

| # | Question | Options | Chosen (2026-09-23) | Needed by | File |
|---|---|---|---|---|---|
| D-02 | MANAGER's financial access | a) none · b) view invoices & payments · c) full like ACCOUNTANT | **b) View invoices & payments only**; no expenses or financial reports | Step 15 | 02 |
| D-03 | ACCOUNTANT's access to projects/tasks | a) none · b) view only · c) full | **b) View only** | Step 13 | 02 |
| D-05 | Can EMPLOYEEs see customer info? | a) no · b) basic info of their projects' customers · c) full list | **b)** | Step 12–13 | 02 |
| D-07 | Can EMPLOYEEs create tasks? | a) no · b) yes, in their projects | **a) No** | Step 13 | 02 |
| D-08 | Can ACCOUNTANTs create/edit customers? | a) yes (not archive) · b) view only | **a) Yes** | Step 12 | 02 |
| D-09 | Can MANAGERs invite users? | a) no · b) employees only · c) any role except OWNER/ADMIN | **a) No** | Step 11 | 02 |
| D-20 | Employee expense claims with approval | a) not in V1 · b) yes | **a) Not in V1** | Step 17 | 02 |
| D-21 | Can CLIENTs upload files? | a) no · b) yes, to their projects | **a) No in V1** | Step 18 | 02, 10 |
| D-22 | Can EMPLOYEEs upload documents? | a) yes, to their tasks/projects · b) no | **a) Yes** | Step 18 | 02, 10 |
| D-23 | Invitation expiry | 3 / **7** / 14 / 30 days | **7 days** | Step 11 | 04, 05 |
| D-25 | What happens when a subscription expires? | a) read-only · b) blocked completely · c) nothing (honour system) | **a) Read-only** | Step 22 | 02, 12 |
| D-30 | Do CLIENTs see platform announcements? | a) no · b) yes | **a) No** | Step 22 | 02, 11 |
| D-33 | Email provider (production SMTP + invitation emails) | Resend · Brevo · Amazon SES · Postmark · other | **Resend** (needs a domain you own) | Step 11 (optional) / Step 24 (required) | 05, 13 |
| D-34 | How invitations are delivered | a) copy-link always + email via our provider · b) Supabase "invite user" email (uses secret key) · c) copy-link only | **a)** | Step 11 | 05 |
| D-35 | Password rules | a) ≥ 8 chars with a letter and a number · b) ≥ 12 chars · c) Supabase default | **a)** + leaked-password check on paid plan | Step 9 | 05 |
| D-36 | Who can sign up? | a) open signup with trial (PLATFORM_ADMIN can switch off) · b) invite / approval only | **a)** | Step 9–10 | 05 |
| D-37 | Max organizations one user can own | 1 / **3** / unlimited | **3** (PLATFORM_ADMIN can raise) | Step 10 | 05 |
| D-40 | Invoice PDF / emailing | a) print view + browser "Save as PDF" · b) server-generated PDF · c) + email invoice | **a) in V1** | Step 15 | 09 |
| D-41 | Basis of "income vs expenses" report | a) cash basis (received − expenses) + invoiced shown · b) accrual (invoiced − expenses) | **a)** | Step 20 | 09 |
| D-42 | Do CLIENTs see void invoices? | a) yes, stamped VOID · b) hidden | **a) Yes** | Step 15 | 07 |
| D-43 | File size and types | size: 5 / **10** / 25 MB; types: PDF, images, Office, CSV, TXT | **10 MB**; PDF, JPEG, PNG, WEBP, DOCX, XLSX, CSV, TXT | Step 18 | 10 |
| D-44 | Logo storage | a) separate public-read bucket for logos only · b) private + signed links | **a)** | Step 18 | 10 |
| D-46 | Inviting a disabled member | a) accepting re-enables their membership · b) refuse | **a)** | Step 11 | 05 |
| D-47 | Plan names, prices, currency, limits (users, client logins, customers, storage) | **Only you can decide** | **STILL OPEN** — suggested shape: trial / basic / pro in PKR | Step 22 | 12 |
| D-48 | Trial length | 7 / **14** / 30 days | **14 days** (changeable in platform settings) | Step 22 | 12 |
| D-49 | Timeline after expiry | a) read-only at once, may suspend after 30 days, never auto-delete · b) suspend at once | **a)** | Step 22 | 12 |
| D-52 | Product name, domain, brand colour | **Only you can decide** | **STILL OPEN** — working name and neutral blue until then | Step 5 (working name), Step 24 (final) | 13, 14 |
| D-55 | CSV export in V1 | a) yes, finance lists + reports for allowed roles · b) no | **a) Yes**, max 10,000 rows | Step 20 | 16 |
| D-56 | Separate Supabase projects for dev and prod | a) yes · b) one project | **a) Yes** | Step 7 (dev) / 24 (prod) | 17 |
| D-57 | Hosting region | Supabase region + Vercel function region | **Mumbai (`ap-south-1` / `bom1`)** — verify availability | Step 7 | 17 |
| D-59 | Where database tests run | a) cloud dev project, rolled back · b) local Supabase in Docker | **a)** | Step 8 | 16 |

## C. Can wait

| # | Question | Options | Chosen (2026-09-23) | Needed by | File |
|---|---|---|---|---|---|
| D-04 | Subdomains per organization later | a) keep `/app/[orgSlug]` · b) `slug.yourdomain.com` in V2 | **a) Keep paths**; revisit after launch | V2 | 01 |
| D-26 | Interface language | a) English only · b) + Urdu | **a) English in V1** | V2 | 01 |
| D-27 | Retention of logs / notifications | logs: forever / 1–5 years; read notifications: 30 / **90** days | **Logs forever; read notifications deleted after 90 days** | Step 19 | 04, 11 |
| D-28 | Can the organization slug change? | a) only PLATFORM_ADMIN on request · b) OWNER can change · c) never | **a)** | Step 22 | 04 |
| D-38 | Two-factor login | a) not in V1 · b) optional now · c) required for PLATFORM_ADMIN now | **a)**; V2 starts with PLATFORM_ADMIN | V2 | 05 |
| D-39 | Change email from profile | a) not in V1 · b) yes | **a)** | V2 | 05 |
| D-45 | Profile photos | a) not in V1 (initials) · b) yes | **a)** | V2 | 05 |
| D-50 | Automated payment gateway | a) manual billing in V1 · b) gateway now | **a)**; evaluate local gateway / merchant of record later | V2 | 12 |
| D-51 | Dark mode | a) light only · b) light + dark | **a) Light only in V1** | V2 | 14 |
| D-53 | Rate-limit method | a) small table in private schema · b) external service (Upstash) | **a)** | Step 11 | 13 |
| D-54 | Error monitoring service | a) Vercel logs only · b) Sentry now | **a)**; add Sentry with paying customers | Step 23 | 13 |
| D-58 | Backups | a) Supabase Pro daily + monthly manual export · b) + point-in-time recovery | **a)** | Step 24 | 17 |
| D-60 | Email / WhatsApp notifications | a) V2 · b) V1 | **a) V2** | V2 | 11 |
| D-61 | Automated browser tests | a) small Playwright smoke suite in Step 23 · b) none · c) from the start | **a)** | Step 23 | 16 |

---

## Count

- A. Blocks the database: **16**
- B. Blocks a later phase: **31** (29 answered; **D-47 and D-52 still open**)
- C. Can wait: **14**
- Total: **61** (59 answered, 2 open)
