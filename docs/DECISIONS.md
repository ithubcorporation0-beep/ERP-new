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
