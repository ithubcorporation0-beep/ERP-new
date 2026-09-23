# 12 — Billing & Subscriptions

> **Plan** = a package the SaaS sells (e.g. Basic, Pro) with limits.
> **Subscription** = which plan one organization is on, and until when it is paid.
> **Manual billing** = the organization pays outside the app (bank transfer, JazzCash, Easypaisa) and the PLATFORM_ADMIN records it and extends access by hand.

Tables: `plans`, `subscriptions`, `subscription_payments`, `platform_settings` (`04-database.md` §4.1).

---

## 1. Plans and limits

All names, prices and numbers are **D-47** — you decide them. The table below is only a **placeholder example** so the design can be tested; it is not a pricing recommendation.

| Plan code | Users (non-client) | Client logins | Customers | Storage | Price / month |
|---|---|---|---|---|---|
| `trial` | [D-47] | [D-47] | [D-47] | [D-47] | 0 |
| `basic` | [D-47] | [D-47] | [D-47] | [D-47] | [D-47] |
| `pro` | [D-47] | [D-47] | [D-47] | [D-47] | [D-47] |

- An empty limit in the database means "unlimited".
- **What counts:** users = active memberships with role ≠ client; client logins = active client memberships; customers = non-archived customers; storage = Σ `documents.size_bytes` + logo.
- Pending invitations count toward user/client limits (so an organization cannot invite 50 people on a 5-user plan).
- Features are the **same on every plan in V1**; plans differ only by limits. (Feature-gating by plan is future work.)
- Plans are created and edited by PLATFORM_ADMIN at `/platform/plans`.

## 2. Trial

- Every new organization starts on the `trial` plan with status `trialing` (created by `create_organization()` once Step 22 exists; existing organizations get a trial row in the Step 22 migration).
- Length: **14 days** (D-48) (setting `default_trial_days` in `platform_settings`, so it can be changed without code).
- During the last 7 days the OWNER sees a banner "Your trial ends on 30 Sep — how to pay" and one `subscription_expiring` notification.

## 3. Subscription statuses and what users can do

| Status | Meaning | Organization can |
|---|---|---|
| `trialing` | Trial running (`trial_ends_at` in the future) | Everything (within trial limits) |
| `active` | Paid (`current_period_end` ≥ today) | Everything (within plan limits) |
| `expired` | Trial or paid period is over | **Read-only** (D-25): view, search, print, download; **no** create/edit/delete, no invitations. OWNER can still open `/billing` |
| `cancelled` | OWNER asked to stop | Same as `expired` |
| Organization `suspended` (separate field `organizations.status`) | Blocked by PLATFORM_ADMIN | **Nothing** — suspended page only |

**Checked live from dates.** `private.org_writable(org)` returns true only if (`trialing` and `trial_ends_at` > now) or (`active` and `current_period_end` ≥ today in the organization timezone). No background job has to "flip" statuses for access to be correct; the stored `status` is updated when PLATFORM_ADMIN acts or on the next platform-dashboard load, only for display.

Timeline after expiry (D-49):

```
period end ──► read-only immediately (banner for everyone, payment instructions for OWNER)
          ──► after 30 days still unpaid: PLATFORM_ADMIN may suspend (manual decision, with reason)
          ──► data is never deleted automatically; only on OWNER request (D-24)
```

## 4. Payment collection (V1 = manual billing)

**Why manual:** Stripe does not list Pakistan as a supported country for businesses (verify on Stripe's website before any decision). Local gateways need a registered business and integration work. Manual billing lets the platform start charging on day one.

Flow:
1. OWNER opens `/billing` → sees current plan, usage vs limits, end date, and **payment instructions** (bank account / JazzCash / Easypaisa details and "send the receipt to …" — stored in `platform_settings.billing_instructions`, editable by PLATFORM_ADMIN).
2. OWNER pays and sends proof (WhatsApp/email — outside the app in V1).
3. PLATFORM_ADMIN opens `/platform/subscriptions` → organization → **Record payment**: plan, amount, method, reference, paid on, period start/end (defaults: start = max(today, current end + 1 day), end = start + 1 month or 1 year) → function `activate_subscription(...)` in one transaction:
   - inserts `subscription_payments`,
   - sets `subscriptions` plan, status `active`, period dates,
   - logs `subscription.activated`, notifies OWNER.
4. A mistake is corrected by **voiding** the subscription payment (reason) and recording again — never deleted.

**Plan change:** OWNER asks (outside the app or via a "Request change" button that notifies platform admins — optional); PLATFORM_ADMIN changes the plan. Downgrade is blocked if the organization is above the new limits ("This organization has 12 users; Basic allows 5").

**Invoices for the SaaS itself** (a bill to the organization): not generated in V1; the OWNER sees payment history on `/billing`. (Future.)

**Automated payment gateway:** future — D-50.

## 5. How limits are enforced (server + database)

| Limit | Checked in |
|---|---|
| Users / client logins | `invite` Server Action **and** `accept_invitation()` / `change_member_role()` / `set_member_status()` (re-enabling) database functions |
| Customers | `create customer` Server Action **and** a `before insert` trigger on `customers` (also when restoring from archive) |
| Storage | `prepareUpload` Server Action (current usage + new file size) **and** `confirmUpload` check |
| Writes while expired | `can_write()` in every RLS insert/update/delete policy + RPC functions (§3) |

- One database function `private.org_limits(org)` returns the current plan limits and usage, used by all checks and by the `/billing` page, so the numbers always match.
- Error messages name the limit and the fix: "Your plan allows 5 users. Ask the owner to upgrade."
- Limits never delete or hide existing data; they only stop adding more.

## 6. What the organization sees vs the platform

| Information | OWNER | ADMIN | Others | PLATFORM_ADMIN |
|---|---|---|---|---|
| Plan name | ✅ | ✅ | ❌ | ✅ |
| Limits & usage | ✅ | ✅ (read) | ❌ | ✅ |
| End date, status | ✅ | ✅ | ❌ | ✅ |
| Payment history | ✅ | ❌ | ❌ | ✅ |
| Internal notes | ❌ | ❌ | ❌ | ✅ |
| Read-only / suspended banners | everyone in the organization sees them | | | |

Organizations read this through `get_my_subscription(org)` (never the tables directly), so platform notes stay private.

## 7. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-25 | (from `02`) What happens when a subscription expires? | **Read-only** until renewed. | Businesses keep access to their records; clear reason to pay. |
| D-47 | Plan names, prices, currency and limits | **STILL OPEN — you decide before Step 22.** Suggested shape: trial, basic, pro, priced in PKR, limits on users, client logins, customers, storage. | Pricing is a business decision; the software only needs the numbers. |
| D-48 | Trial length | **14 days**, changeable in platform settings. | Long enough to set up and try invoicing; short enough to convert. |
| D-49 | Timeline after expiry | **Read-only at once; PLATFORM_ADMIN may suspend after 30 days unpaid; never auto-delete.** | Fair to businesses, keeps the decision to suspend with a human in V1. |
| D-50 | Automated payment gateway (future) | **Manual in V1.** Later: evaluate a Pakistani gateway (bank/wallet-based) or a merchant-of-record service that pays out to Pakistan — verify availability then. | Avoids integration work and legal setup before there are paying customers. |
