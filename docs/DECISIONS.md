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
