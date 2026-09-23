# 11 — Notifications & Audit Log

> **Notification** = a short in-app message to one person ("Task X was assigned to you").
> **Audit log** (table `activity_logs`) = a permanent record of who changed what and when, for trust and for solving disputes.

---

## Part 1 — Notifications

### 1.1 V1 scope
- **In-app only**: bell icon with unread count, dropdown, `/notifications` page.
- **No email, WhatsApp or SMS notifications in V1** (future, §1.8). Only auth emails and invitation emails are sent by email (`05-auth-onboarding.md`).
- Platform announcements are **not** notifications; they are shown as a banner from the `platform_announcements` table (§1.6).

### 1.2 Events and recipients

The person who caused the event never gets a notification about it.

| Type (`notifications.type`) | Triggered when | Recipients | Link |
|---|---|---|---|
| `task_assigned` | Task created with an assignee, or assignee changed | New assignee | `/app/{slug}/tasks/{id}` |
| `task_unassigned` | Assignee changed away from someone | Previous assignee | `/app/{slug}/tasks` |
| `task_status_changed` | Task becomes `done` or `blocked` | Task creator | task |
| `task_comment_added` | New comment | Assignee + task creator | task |
| `project_member_added` | Added to a project | That member | `/app/{slug}/projects/{id}` |
| `project_status_changed` | Project status changes | Linked CLIENT users of that customer | project |
| `invoice_issued` | Invoice issued | Linked CLIENT users of that customer | `/app/{slug}/invoices/{id}` |
| `invoice_voided` | Invoice voided | Linked CLIENT users | invoice |
| `payment_recorded` | Payment recorded | Linked CLIENT users; OWNER | `/app/{slug}/payments/{id}` |
| `payment_reversed` | Payment reversed | Linked CLIENT users; OWNER | payment |
| `document_uploaded` | File added to a task / made visible to client | Task assignee / linked CLIENT users | the record |
| `member_joined` | Invitation accepted | Inviter + OWNER | `/app/{slug}/team` |
| `member_role_changed` | Role changed / membership disabled or re-enabled | That member (in-app; if disabled they will see it only when re-enabled) | `/app/{slug}` |
| `ownership_transferred` | Ownership transferred | New OWNER and previous OWNER | `/app/{slug}/settings` |
| `invitation_received` | Invitation created for an email that already has an account | That user (shown on `/onboarding` and in the bell of their other organizations) | `/invite/...` is **not** stored; the user opens it from `/onboarding` pending invitations |
| `subscription_expiring` | First visit in the last 7 days before trial/period end | OWNER | `/app/{slug}/billing` |
| `subscription_changed` | PLATFORM_ADMIN activates, extends, changes plan, marks expired | OWNER | billing |
| `organization_suspended` | Organization suspended / re-activated | OWNER (visible when active again; the suspended page explains the rest) | `/app/{slug}` |

"Linked CLIENT users" = active memberships with role `client` and `customer_id` = the record's customer.

Notes:
- `invitation_received` is stored with the **inviting** organization's `organization_id`, but its RLS lets only the recipient read it. It does not require membership of that organization (special case in the notifications select policy: `recipient_user_id = auth.uid()` and type `invitation_received`).
- Overdue-invoice and due-task reminders need a scheduled job and are **V2**; in V1 overdue items are highlighted on dashboards.

### 1.3 How notifications are created

- By **database triggers and functions** right after the change (e.g. the `tasks` trigger inserts `task_assigned` when `assignee_membership_id` changes; `record_payment()` inserts `payment_recorded`).
- One shared function `private.notify(org, recipient_user_ids[], type, title, body, link_path, entity_table, entity_id)` inserts the rows and skips the acting user.
- Because they are created in the same transaction as the change, a notification can never be "forgotten" and never exists for a change that was undone.
- The browser can never insert notifications (no insert policy).

### 1.4 Table

`notifications` — columns in `04-database.md` §4.4: `organization_id`, `recipient_user_id`, `type`, `title`, `body`, `link_path`, `entity_table`, `entity_id`, `read_at`, `created_at`.
Title/body are plain text written by our code (no user-controlled HTML), for example: title "New task assigned", body "Cut slabs — Kitchen marble (due 30 Sep)".

### 1.5 Read / unread and notification center

- **Bell** in the header: unread count for the **current organization** (+ a small dot on the organization switcher for other organizations with unread items).
- Count refreshes on every page navigation and every 60 seconds while the tab is visible (simple polling; live "realtime" updates are not needed in V1).
- Dropdown: latest 10, unread in bold, "Mark all as read", "See all".
- `/notifications`: 25 per page, filter All / Unread.
- Clicking a notification marks it read (`mark_notifications_read`) and opens `link_path`. The target page does its own permission check; if the person lost access they see "Not found".

### 1.6 Platform announcements

- Shown as a banner at the top of every business panel while published and between `starts_at` and `ends_at`; colour by level (info / warning / critical).
- Dismissing hides it in that browser (stored locally, not in the database). Critical ones cannot be dismissed.
- Not shown to CLIENT users (D-30).

### 1.7 Permissions

| Who | Can |
|---|---|
| Recipient | Read own notifications, mark read |
| Anyone else (including OWNER, PLATFORM_ADMIN) | Nothing — nobody can read other people's notifications |
| Browser | Cannot create, edit or delete notifications |

### 1.8 Future: email / WhatsApp / SMS

Design ready for later: add a per-user `notification_preferences` table (which types by which channel) and a background sender that reads new `notifications` rows. Candidates: email through the D-33 provider; WhatsApp Business Cloud API; local SMS gateway. Not in V1 (D-60).

### 1.9 Retention

A daily database job (Supabase **pg_cron** — a built-in scheduler that runs SQL on a timetable) deletes **read** notifications older than 90 days (D-27). Unread ones are kept.

---

## Part 2 — Audit log (`activity_logs`)

### 2.1 What is recorded

| Field | Source |
|---|---|
| Who | `actor_user_id` = `auth.uid()` (empty for system jobs) |
| What action | `insert` / `update` / `delete`, or a named event (`invoice.issued`, `invoice.voided`, `payment.recorded`, `payment.reversed`, `member.role_changed`, `member.disabled`, `ownership.transferred`, `invitation.created`, `invitation.accepted`, `organization.suspended`, `subscription.activated`) |
| Which record | `table_name` + `record_id` |
| When | `created_at` |
| Organization | `organization_id` (empty for platform-level events) |
| Before / after | `changes` jsonb — **only changed fields** for updates: `{"status": {"old": "draft", "new": "sent"}}`; all values for insert; all values for delete |
| IP / user agent | When available (§2.3) |

### 2.2 How — database triggers

- One shared trigger function `private.audit_row_change()` (security definer) is attached `after insert or update or delete` to **every business table**: organizations, organization_settings, memberships, invitations, customers, projects, project_members, tasks, task_comments, services_products, invoices, invoice_items, payments, expense_categories, expenses, documents, and platform tables (plans, subscriptions, subscription_payments, platform_settings, platform_announcements, platform_admins, profiles.status).
- Because it runs **inside the database**, every change is recorded — whether made by our website, a database function, or a direct API call. Nothing can be forgotten in the app code.
- Named business events (`invoice.issued` etc.) are written by the database functions in addition, because they are easier to read in the log viewer than raw column changes.
- Updates that change nothing (or only `updated_at`) are skipped.
- **Not audited**: `notifications`, `number_sequences`, `activity_logs` itself (would be noise or loops).

### 2.3 IP address and user agent

The server-side Supabase client sends two extra request headers with every call: the visitor's IP (from Vercel's `x-forwarded-for`) and browser user agent. The audit trigger reads them from the request information that Supabase makes available inside the database. If someone calls the API directly, these values are whatever they sent, so the log viewer labels them "reported IP". They are informational only, never used for security decisions.

### 2.4 What is never logged

- Passwords, password hashes, tokens, API keys, `invitations.token_hash`, signed URLs, session data.
- The trigger has a per-table **exclude list** of columns; `token_hash` is always excluded. Supabase's own `auth` tables are not audited by us at all (Supabase keeps its own auth logs).
- File **downloads** are not logged in V1 (they would create too many rows); uploads and deletes are.

### 2.5 Protection

- No update or delete policy; `update`, `delete`, `truncate` privileges revoked from `anon` and `authenticated` → **nobody can edit or delete logs through the app**, not even the OWNER.
- Only the audit trigger function and database functions (security definer) insert rows.
- Only the permanent deletion of a whole organization (D-24) removes its logs.

### 2.6 Who can read

| Who | What |
|---|---|
| OWNER, ADMIN | All logs of their organization (`/app/{slug}/activity`) |
| PLATFORM_ADMIN | Platform-level logs (`organization_id` empty) + platform actions on organizations. Tenant business logs only if D-01 allows |
| Everyone else | Nothing. (A record's detail page may show a short "History" built from logs for OWNER/ADMIN only) |

### 2.7 Viewer (Step 21)

Filters: date range (default last 7 days), person, module/table, action. 50 rows per page. Detail drawer shows old → new values with friendly field names; IDs are turned into names where possible (e.g. customer name).

### 2.8 Retention

Kept forever in V1 (D-27). Size estimate: a busy small business creates a few thousand rows per month — tiny for PostgreSQL.

## Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-60 | When to add email / WhatsApp notifications | **V2**, starting with email for `invoice_issued` and `task_assigned`, with per-user preferences. | Needs the email provider (D-33) and preference screens; in-app is enough to launch. |

Referenced: D-01, D-24, D-27, D-30, D-33.
