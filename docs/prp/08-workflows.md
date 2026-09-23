# 08 — Workflows

> A **workflow** = the steps of one business process from start to end: who starts it, what happens, what changes in the database, who is told, and what can go wrong.

Common to every workflow below:
- Every form is validated on the server with Zod; errors appear next to the field.
- Every change runs the server role check **and** RLS.
- Every change writes `activity_logs` (by trigger or database function).
- Success → a green toast (small pop-up) and the page refreshes. Failure → a red toast with a plain-English message; never a technical error or stack trace.
- If the organization is read-only (expired subscription, D-25) every write shows: "Your subscription has expired. You can view data but not change it. Ask the owner to renew."
- Notifications are **in-app only** in V1 (`11-notifications-audit.md`).

---

## 1. Organization signup & onboarding

| | |
|---|---|
| Started by | A new visitor |
| Permissions | None to start; verified email to create an organization |
| Steps | 1. `/signup` → 2. confirmation email → 3. `/auth/confirm` → 4. `/onboarding` → 5. fill name, slug, currency, timezone → 6. `create_organization()` → 7. `/app/<slug>` owner dashboard with getting-started checklist |
| Database | `auth.users` (Supabase), `profiles` (trigger), `organizations`, `organization_settings`, `memberships` (owner), `expense_categories` (starter, from Step 17), `subscriptions` (trial, from Step 22), `activity_logs` |
| Notified | The new owner (welcome notification) |
| Errors | Email already used (generic "check your email" message); weak password; slug taken / invalid / reserved; signups closed (D-36); too many owned organizations (D-37); email not verified |

## 2. User invitation

| | |
|---|---|
| Started by | OWNER or ADMIN |
| Permissions | `owner`, `admin`; role may not be OWNER |
| Steps | 1. `/team` → Invite → email, role (+ customer for CLIENT) → 2. server checks (not already active member, no pending invite, plan limit) → 3. invitation saved with hashed token, expires in 7 days → 4. link shown for copying + email if provider set (D-34) → 5. invitee opens `/invite/<token>` → signs up or logs in with the **same email** → 6. Accept → `accept_invitation()` → 7. redirected to `/app/<slug>` |
| Database | `invitations` (pending → accepted), `memberships` (new or re-enabled — D-46), `activity_logs` |
| Notified | Inviter + OWNER: "X joined as MANAGER" |
| Errors | Email already a member; pending invite exists ("Resend instead?"); user limit reached ("Upgrade your plan"); CLIENT without customer; link expired/cancelled/used; logged in with another email ("This invite was sent to a***@…") |
| Related | **Resend** (new token, old link dead), **Cancel**, **Change role**, **Disable/enable member**, **Transfer ownership** (OWNER picks an active non-client member → confirm by typing the organization name → roles swap: new OWNER, old OWNER becomes ADMIN → both notified) |

## 3. Employee assignment

| | |
|---|---|
| Started by | OWNER, ADMIN, MANAGER |
| Steps | **To a project**: project → Members → Add member (active non-client members only). **To a task**: task form → Assignee (active non-client member). Assigning a task in a project automatically adds the person to that project's members |
| Database | `project_members` (insert/delete), `tasks.assignee_membership_id`, `activity_logs` |
| Notified | The employee: "You were added to project X" / "Task Y was assigned to you". When a task is re-assigned, the previous assignee is told "Task Y was re-assigned" |
| Errors | Member disabled; CLIENT chosen (not allowed); removing a member who still has open tasks in the project → warning "They still have 3 open tasks here — reassign them first" |

## 4. Customer

| | |
|---|---|
| Started by | OWNER, ADMIN, MANAGER, ACCOUNTANT (D-08) |
| Steps | Create (name required, contact info optional) → edit → optionally invite a client login from the customer page → archive when no longer active (OWNER/ADMIN/MANAGER) → restore if needed |
| Database | `customers`, `invitations`/`memberships` (client login), `activity_logs` |
| Notified | Nobody on create/edit (no noise); client login invite as in §2 |
| Errors | Name missing/too long; archiving a customer with unpaid invoices → warning (allowed); new project/invoice for an archived customer → blocked "Restore the customer first" |
| Plan limit | Max customers per plan (from Step 22) |

## 5. Project

| | |
|---|---|
| Started by | OWNER, ADMIN, MANAGER |
| Steps | Create (customer optional — D-17, name, dates, status `active` by default) → add members → add tasks → change status (`planned` / `active` / `on_hold` / `completed` / `cancelled`) → archive |
| Database | `projects`, `project_members`, `tasks`, `activity_logs` |
| Notified | Members added; linked CLIENT users when status changes (e.g. "Project X is now Completed") |
| Errors | Due date before start date; archived customer; completing with open tasks → warning, allowed |

## 6. Task

| | |
|---|---|
| Started by | OWNER, ADMIN, MANAGER (create); assignee EMPLOYEE (status + comments) |
| Steps | Create (title, project optional, assignee, priority, due date) → assignee works and changes status `todo` → `in_progress` → `done` (or `blocked`) → comments along the way → manager may reopen → archive old tasks |
| Database | `tasks` (`completed_at` set/cleared by trigger), `task_comments`, `project_members` (auto-add), `documents` (attachments), `activity_logs` |
| Notified | Assignee on assignment; task creator when status becomes `done` or `blocked`; assignee + creator on new comment (not the comment's author) |
| Errors | Employee tries to edit anything but status → refused; assignee disabled; due date in the past → allowed with warning |

## 7. Invoice

| | |
|---|---|
| Started by | OWNER, ADMIN, ACCOUNTANT |
| Steps | 1. New invoice → choose customer (+ project optional) → dates default from settings → 2. add lines (pick a service/product or type freely; quantity, price, discount, tax %) → totals recalculated by the database after each save → 3. save as **draft** (can edit/delete) → 4. **Issue** → `issue_invoice()` gives the number, snapshots customer details, status `sent` → 5. print / share (print view, browser "Save as PDF" — D-40) → 6. payments move it to `partially_paid` / `paid` → 7. if wrong: **Void** (reason) and **Duplicate as new draft** (D-31) |
| Database | `invoices`, `invoice_items`, `number_sequences`, `activity_logs` |
| Notified | Linked CLIENT users on issue ("New invoice INV-2026-0007"); on void ("Invoice INV-… was voided") |
| Errors | No lines ("Add at least one line"); total is 0 → allowed with warning; archived customer; editing an issued invoice → "Issued invoices cannot be edited. Void it and duplicate it."; voiding an invoice with payments → "Reverse the payments first"; two people issuing at the same moment → both succeed with different numbers |

## 8. Payment

| | |
|---|---|
| Started by | OWNER, ADMIN, ACCOUNTANT |
| Steps | From an invoice (status `sent`/`partially_paid`) → Record payment → amount (defaults to the balance), date (default today), method, reference, notes → `record_payment()` → invoice `amount_paid`, balance and status update automatically. **Reverse**: payment → Reverse → reason → `reverse_payment()` → payment `reversed`, invoice balance goes back up, status recalculated |
| Database | `payments`, `invoices` (amount_paid, status), `activity_logs` |
| Notified | Linked CLIENT users ("Payment of Rs 5,000 received for INV-…"); OWNER (unless they recorded it); on reversal the same people |
| Errors | Amount ≤ 0; amount more than balance ("Maximum is Rs 3,500.00" — D-14); date in the future; invoice draft or void; payment already reversed |

## 9. Expense

| | |
|---|---|
| Started by | OWNER, ADMIN, ACCOUNTANT |
| Steps | New expense → category, amount, date, method, payee, description, project (optional) → save → attach receipt (documents) → edit if a mistake → **Void** with reason if recorded by mistake |
| Database | `expenses`, `expense_categories`, `documents`, `activity_logs` |
| Notified | Nobody (V1) |
| Errors | Amount ≤ 0; archived category; editing a void expense → refused |

## 10. Document

| | |
|---|---|
| Started by | Roles allowed by matrix §3.9 (`02-roles-permissions.md`) |
| Steps | On a customer/project/task/invoice/expense page → Upload → file checked (type, size, plan storage limit) → uploaded straight to private storage → document row saved → optional "Visible to client" switch → download via short-lived signed link → delete (per rules) |
| Database | `documents`, Storage object, `activity_logs` |
| Notified | Task assignee when a file is added to their task; linked CLIENT users when a document is made visible to them |
| Errors | File too big / type not allowed (D-43); storage limit reached; upload interrupted ("Upload failed, try again"); no permission |
| Details | `10-documents.md` |

## 11. Notification

| | |
|---|---|
| Started by | The system (database triggers/functions after the events above) |
| Steps | Event happens → notification row created for each recipient (never for the person who did the action) → bell count updates on next page load / refresh → user opens the bell → clicks → linked page opens and the notification is marked read → "Mark all as read" |
| Database | `notifications` |
| Errors | Linked record no longer visible (e.g. user removed from project) → page shows "Not found"; notification still marked read |
| Details | Events list and table in `11-notifications-audit.md` |

## 12. Subscription (plan change / expiry / suspension)

| | |
|---|---|
| Started by | System (trial start at onboarding), OWNER (asks for a plan change or pays), PLATFORM_ADMIN (activates, extends, suspends) |
| Steps | **Trial**: created at onboarding (length D-48) → banner "Trial ends in N days" for OWNER. **Pay**: OWNER sees payment instructions on `/billing` → pays by bank transfer / JazzCash / Easypaisa → sends proof (outside the app, V1) → PLATFORM_ADMIN records the payment and sets the new period → status `active`. **Plan change**: OWNER requests → PLATFORM_ADMIN changes plan (checks the organization is within the new plan's limits). **Expiry**: when the period end passes, the organization becomes **read-only** (D-25) — checked live from the dates, no background job needed. **Suspension**: PLATFORM_ADMIN suspends (unpaid for long, abuse) → nobody can open the organization → activate again when resolved |
| Database | `subscriptions`, `subscription_payments`, `organizations.status`, `activity_logs` |
| Notified | OWNER: trial/period ending (banner on every visit in the last 7 days + notification when first seen), plan activated/extended, suspended |
| Errors | Downgrade over limits ("This organization has 12 users; Basic allows 5"); writes while read-only (message above) |
| Details | `12-billing-subscriptions.md` |

## 13. Full business flow

```
Customer → Project → Tasks → Completion → Invoice → Payment → Report
```

| Stage | Who | What happens | Records |
|---|---|---|---|
| 1. Customer | MANAGER / ADMIN | New customer "Ali Builders" is created; optionally a client login is invited | `customers`, `invitations` |
| 2. Project | MANAGER | Project "Kitchen marble — Ali Builders" created, employees added | `projects`, `project_members` |
| 3. Tasks | MANAGER | Tasks "Measure site", "Cut slabs", "Install" assigned with due dates | `tasks` |
| 4. Work | EMPLOYEE | Updates status, comments, uploads photos | `tasks`, `task_comments`, `documents` |
| 5. Completion | MANAGER | All tasks `done` → project `completed`; client sees the new status | `projects` |
| 6. Invoice | ACCOUNTANT | Invoice created from the project (customer + project pre-filled), lines from the price list, issued → `INV-2026-0012` | `invoices`, `invoice_items`, `number_sequences` |
| 7. Payment | ACCOUNTANT | Customer pays half by bank transfer, later the rest in cash → invoice `partially_paid` then `paid` | `payments`, `invoices` |
| 8. Report | OWNER | Dashboard: received this month goes up; receivables go down; project expenses vs invoiced visible in reports | reports read-only |

At every stage the CLIENT (if invited) sees their project status, invoices and payments; nothing else.

## 14. Decisions for this file (answered 2026-09-23 — "use recommendation")

None new. Depends on: D-08, D-14, D-17, D-25, D-31, D-48, D-34, D-36, D-37, D-40, D-43, D-46.
