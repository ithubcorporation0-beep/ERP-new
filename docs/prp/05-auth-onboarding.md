# 05 — Authentication & Onboarding

> **Authentication** = proving who you are (login).
> **Authorization** = deciding what you may do (roles) — see `06-authorization-rls.md`.
> **Onboarding** = the first steps after signup (creating the organization).

We use **Supabase Auth** (Supabase's built-in login system) with **email + password**.
In Next.js we use the `@supabase/ssr` package, which stores the login session in secure browser **cookies** (small pieces of data the browser sends with every request). The deprecated `@supabase/auth-helpers` packages are **not** used.

The exact function names below (e.g. `getClaims()`, `verifyOtp()`) are checked against the official docs for the installed versions in Step 7/9, as `CLAUDE.md` requires.

---

## 1. Pages and routes

| Route | Who can open it | Purpose |
|---|---|---|
| `/` | Everyone | Public home page (what the software is, pricing, login/signup buttons) |
| `/signup` | Logged-out | Create an account |
| `/login` | Logged-out | Log in |
| `/forgot-password` | Everyone | Ask for a password reset email |
| `/reset-password` | User who clicked the reset link | Choose a new password |
| `/auth/confirm` | Route Handler (no page) | Receives email links (verification, reset, email change) and creates the session |
| `/auth/signout` | Logged-in (POST only) | Logs out |
| `/verify-email` | Logged-in, email not verified | "Check your inbox" + resend button |
| `/account-disabled` | Logged-in, disabled account | Explanation + support contact |
| `/onboarding` | Logged-in, verified | Create an organization, or see pending invitations |
| `/select-organization` | Logged-in with 2+ memberships | Choose an organization |
| `/invite/[token]` | Everyone | Invitation landing page |
| `/organization-suspended` | Logged-in member of a suspended org | Explanation |
| `/app/[orgSlug]/...` | Active member of that organization | The organization panels (`07-panels.md`) |
| `/app/[orgSlug]/profile` | Any member | My profile |
| `/platform/...` | PLATFORM_ADMIN | Platform panel |

## 2. Signup

1. User opens `/signup`, enters **full name**, **email**, **password** (+ "I accept the terms").
2. Server Action validates with Zod (email format, password rules — D-35, name 1–100 chars).
3. Server calls Supabase `signUp()` with:
   - `full_name` passed as signup data (used **only** to fill `profiles.full_name` — never for roles),
   - redirect address `NEXT_PUBLIC_SITE_URL + /auth/confirm?next=/onboarding`.
4. Database trigger `handle_new_user()` creates the `profiles` row (status `active`).
5. User sees "Check your email to confirm your account".
6. **Open signup**: anyone may sign up (D-36). PLATFORM_ADMIN can close signups with the platform setting `signups_enabled` (then only people with an invitation link can sign up).

Errors shown: "Please enter a valid email", "Password must be at least 8 characters and include a letter and a number", "Too many attempts, try again in a few minutes". For an email that already exists we show the **same** "check your email" message, so nobody can use the signup form to find out who has an account.

## 3. Email verification

- Supabase sends an email with a link to `/auth/confirm?token_hash=…&type=email&next=/onboarding`. (In Step 9 you will edit the email templates in the Supabase dashboard so the links point to this route — exact clicks given then.)
- `/auth/confirm` calls Supabase `verifyOtp()`; on success the session cookie is set and the user is sent to `next` (only if `next` is a **relative path inside our site** — this stops "open redirect" tricks that send users to fake sites).
- A user who logs in without verifying sees `/verify-email` with a "resend email" button (limited, see batch C rate limits).
- Unverified users cannot create organizations or accept invitations.

## 4. Login

1. `/login`: email + password → Server Action → Supabase `signInWithPassword()`.
2. Wrong email or password → one generic message "Email or password is incorrect" (never say which one).
3. On success → the server runs the **home-path decision** (§8) and redirects.
4. Optional `?next=/app/...` is honoured only if it is a relative path and the user really has access (checked again by that page anyway).

## 5. Logout

A "Log out" item in the user menu sends a POST to `/auth/signout` → Supabase `signOut()` clears the cookies → redirect to `/login`. (POST instead of a simple link, so another website cannot log users out by embedding a link.)

## 6. Password reset

1. `/forgot-password`: user enters email → Supabase `resetPasswordForEmail()` with redirect `/auth/confirm?next=/reset-password`.
2. Always show "If an account exists for this email, we sent a reset link" (does not reveal whether the email exists).
3. Link → `/auth/confirm` creates a temporary recovery session → `/reset-password`.
4. User enters the new password twice → Supabase `updateUser({ password })` → success message → redirect to home path.
5. Logged-in users can also change their password on `/app/[orgSlug]/profile` (current session is enough in V1).

## 7. Session management

- `@supabase/ssr` keeps the session in **httpOnly cookies** (cookies that browser JavaScript cannot read, which protects them from many attacks).
- The **proxy/middleware** refreshes the session on every request (the official `@supabase/ssr` pattern) and redirects logged-out users away from protected routes (§9).
- On the server, the user is always identified with a call that **verifies the token** with Supabase (`getUser()` or `getClaims()` — whichever the current docs recommend). We never trust `getSession()` on the server for security decisions, because it only reads the cookie without checking it.
- Session length: Supabase defaults (short access token automatically refreshed; user stays logged in until logout or long inactivity). No forced idle logout in V1 (D-38 covers extra security later).
- Logging out in one tab logs out all tabs (browser client listens for auth changes).

## 8. How the user's home page is found after login (flow from brief §1.3)

One server function, planned as `resolveHomePath(user)`, runs after login, after email verification and when opening `/`:

```
1. profiles.status = 'disabled'?                        → /account-disabled
2. user is in platform_admins?                          → /platform
      (if they also have memberships, the /platform header shows the organization switcher)
3. load memberships where status = 'active' (with organization status)
      ignore organizations with status 'pending_deletion'
4. 0 memberships                                        → /onboarding
      (shows pending invitations for the user's email, and "Create organization")
5. exactly 1 membership
      organization suspended?                           → /organization-suspended?org=<slug>
      otherwise                                         → /app/<slug>
6. 2+ memberships
      profiles.last_organization_id is one of them and active? → /app/<that slug>
      otherwise                                         → /select-organization
         (list shows each organization with its role; suspended ones are marked and open the suspended page)
```

- The role is read **only** from `memberships` / `platform_admins` (never `user_metadata`).
- `/app/<slug>` then shows the dashboard for that membership's role (`07-panels.md`).
- Every page under `/app/[orgSlug]` repeats the membership check (`requireMembership`, `03-architecture.md`), so bookmarking or typing a URL never skips it.

## 9. Protected routes

| Route group | Check in proxy (fast, first filter) | Check in the page/layout (the real check) |
|---|---|---|
| Public (`/`, `/login`, `/signup`, `/forgot-password`, `/invite/*`, `/auth/*`) | none (logged-in users on `/login`/`/signup` are sent to their home path) | — |
| `/verify-email`, `/onboarding`, `/select-organization`, `/account-disabled`, `/organization-suspended` | logged in | `requireUser()` (+ verified + active where needed) |
| `/app/[orgSlug]/**` | logged in | `requireMembership(slug, roles)` |
| `/platform/**` | logged in | `requirePlatformAdmin()` |

## 10. Profile

`/app/[orgSlug]/profile` (and `/platform/profile`):

- Edit: full name, phone. (Profile photos: D-45 — recommended not in V1; initials are shown instead.)
- Change password.
- Email change: D-39 (recommended V2).
- Shows: my email, my role in this organization, list of my organizations.
- "Leave this organization" (not for OWNER — must transfer ownership first; not for CLIENT — per `02-roles-permissions.md`).

## 11. Account status

| Status | Where | Set by | Effect |
|---|---|---|---|
| Account `active` / `disabled` | `profiles.status` | PLATFORM_ADMIN only | Disabled: login is also blocked in Supabase Auth (admin client use #1 in `03-architecture.md`); any existing session sees `/account-disabled`; all RLS helpers return false |
| Membership `active` / `disabled` | `memberships.status` | OWNER / ADMIN | Disabled: no access to that one organization (other organizations unaffected) |
| Organization `suspended` | `organizations.status` | PLATFORM_ADMIN | Everybody in it sees `/organization-suspended` |

## 12. Onboarding — creating an organization

1. Verified user with no organization opens `/onboarding`.
2. If there are **pending invitations for their email**, they are listed first with "Accept" buttons (§13).
3. "Create organization" form:
   - **Organization name** (2–100 chars),
   - **Slug** — filled automatically from the name (e.g. "Wajid Marble" → `wajid-marble`), editable, live "available / taken" check, rules in `04-database.md`,
   - **Currency** — dropdown of common currencies, default **PKR** (D-12),
   - **Timezone** — dropdown, default **Asia/Karachi**.
4. Server Action: Zod validation → checks (verified email, signups/organization creation allowed, the user owns fewer than the allowed number of organizations — D-37) → calls database function `create_organization(name, slug, currency, timezone)`, which in **one transaction**:
   - inserts `organizations` (status `active`),
   - inserts `organization_settings` with defaults,
   - inserts the caller's `memberships` row with role `owner`,
   - (from Step 17) inserts starter `expense_categories`,
   - (from Step 22) inserts a `subscriptions` row with status `trialing`,
   - writes `activity_logs` (`organization.created`).
5. Redirect to `/app/<slug>` — the OWNER dashboard with a short "getting started" checklist (add logo, invite team, add first customer).

Errors: "This web name is already taken", "You can own at most N organizations — contact support", "Signups are temporarily closed".

## 13. Invitations

### 13.1 Sending (OWNER / ADMIN)

1. `Team → Invite`: email, role (any except OWNER), and **customer** (required when role = CLIENT; the list shows this organization's customers).
2. Server Action: Zod → `requireMembership(slug, [owner, admin])` → checks:
   - no pending invite for the same email in this organization,
   - the email is not already an **active** member,
   - plan limit for users / clients not reached (from Step 22),
   - the customer belongs to this organization (also enforced by the composite FK).
3. Server creates a long random token (32 random bytes), stores **only its SHA-256 hash** in `invitations.token_hash`, `expires_at = now + 7 days` (D-23).
4. Delivery (D-34, recommended):
   - the invite link `NEXT_PUBLIC_SITE_URL/invite/<token>` is shown **once** with a "Copy link" button, so the inviter can send it by WhatsApp,
   - and, when an email provider is configured (D-33), an invitation email is sent from our server with the same link.
   With this choice Supabase's own "invite user" admin feature is **not** used, and admin-client use #2 in `03-architecture.md` is removed.
5. Activity log `invitation.created`.

### 13.2 Resend / cancel

- **Resend**: creates a **new** token (the old link stops working), new 7-day expiry, `send_count + 1`, limited (batch C rate limits).
- **Cancel**: status `cancelled`; the link stops working.

### 13.3 Accepting

1. Person opens `/invite/<token>`.
2. The page calls `get_invitation_preview(token)` (database function that returns **only** organization name, role and a partly hidden email like `a***@gmail.com`, and whether the invite is still valid). Invalid/expired/cancelled → friendly message "This invitation is no longer valid, ask for a new one".
3. Not logged in → buttons "Create account" / "Log in" (both return to this page afterwards; signup pre-fills the email).
4. Logged in → "Accept invitation" button → Server Action → database function `accept_invitation(token)`, which in one transaction checks:
   - token hash matches a `pending` invite that is not expired,
   - the logged-in user's **verified email equals the invited email** (case-insensitive) — so a forwarded link cannot be used by someone else,
   - plan limits,
   - the user is not already an active member (if they are a **disabled** member, the membership is re-enabled with the invited role — D-46),
   then inserts the `memberships` row (with `customer_id` for CLIENT), marks the invite `accepted`, logs `invitation.accepted` and notifies the inviter.
5. Redirect to `/app/<slug>`.

Errors: "This invitation was sent to another email address. Log out and log in with a***@gmail.com", "This invitation has expired", "You are already a member of this organization".

## 14. Organization switcher

- In the header of every panel, a dropdown shows the current organization (logo + name + my role) and my other **active** memberships.
- Choosing one opens `/app/<other-slug>` and stores it in `profiles.last_organization_id` (convenience only).
- PLATFORM_ADMIN also sees a "Platform" entry.
- Also offers "Create new organization" (subject to D-37).

## 15. Email sending

| Email | Sent by | V1 |
|---|---|---|
| Confirm signup | Supabase Auth | ✅ |
| Reset password | Supabase Auth | ✅ |
| Invitation | Our server through the email provider (D-34) | ✅ when provider configured; copy-link always available |
| Notifications by email | — | ❌ (future) |

**Important limit:** Supabase's built-in email service is **only for testing**. It sends very few emails per hour and may refuse to send to addresses that are not members of your Supabase team. Before real customers use the software we must set up **custom SMTP** (a real email-sending service connected to Supabase Auth). Provider: D-33. The same provider sends invitation emails.

## 16. Decisions raised in this file

| # | Question | Recommended default | Why |
|---|---|---|---|
| D-33 | Email provider for production (custom SMTP + invitation emails) | **Resend** (alternatives: Brevo, Amazon SES, Postmark). | Easy setup with Supabase, free tier enough to start, simple API for invitation emails. Needs a domain you own for sending. |
| D-34 | How invitations are delivered | **Copy-link (for WhatsApp) always + email through our provider once D-33 is set up.** Do not use Supabase's admin "invite user" feature. | Works from day one even without email setup; avoids using the secret key for invites. |
| D-35 | Password rules | **At least 8 characters with at least one letter and one number.** Turn on Supabase's leaked-password check when on a paid plan. | Balance between security and ease for non-technical users. |
| D-36 | Who can sign up and create an organization? | **Open signup** with a free trial; PLATFORM_ADMIN can switch signups off. | Needed to get customers without manual work; the switch protects against abuse. |
| D-37 | How many organizations can one user own? | **3** (PLATFORM_ADMIN can raise it for a person). | Stops people creating endless free trials; real multi-business owners are rare. |
| D-38 | Two-factor login (a code from a phone app) | **Not in V1.** V2: optional for everyone, required for PLATFORM_ADMIN first. | Adds setup and support work; V1 users are few and known. |
| D-39 | Changing email address from the profile | **Not in V1** (PLATFORM_ADMIN can help). | Email change needs double confirmation and syncing `profiles.email`; rare. |
| D-45 | Profile photos | **Not in V1** — show initials. | Saves a storage bucket and policies; purely cosmetic. |
| D-46 | Inviting someone who is a disabled member | **Accepting re-enables their membership** with the new role. | Natural way to bring someone back without duplicate rows. |

Referenced: D-12 (currency), D-23 (invite expiry).
