# 05 — Authentication & Onboarding

> **Authentication** = proving who you are (login).
> **Authorization** = deciding what you may do (roles) — see `06-authorization-rls.md`.
> **Onboarding** = the first steps after signup (creating the organization).

**Decision D-62 (2026-09-23): logins are handled by [Clerk](https://clerk.com)**, a specialised login service. Supabase keeps the database, files and security rules (RLS). Clerk answers only "who is this person?"; everything about organizations, roles and permissions stays in our database.

- Clerk provides the sign-up, login, "forgot password", email-verification and new-device screens, and the account menu (`UserButton`). They are styled with Clerk's shadcn theme so they match our design.
- Clerk sends the verification and password-reset emails itself, so Supabase's built-in email service is **not** used for logins.
- Every request our server sends to Supabase carries the person's **Clerk login token**. Supabase checks that token ("third-party auth"), so RLS knows who is asking. In the database the person's id is the Clerk user id (text like `user_2abc…`), read by `private.current_user_id()` (`06-authorization-rls.md`).
- Package: `@clerk/nextjs` (+ `@clerk/ui` for the theme). `@supabase/ssr` is no longer used.

---

## 1. Pages and routes

| Route | Who can open it | Purpose |
|---|---|---|
| `/` | Everyone | Public home page (Log in / Sign up buttons, or the account menu when logged in) |
| `/pricing` | Everyone | Public plans page (from `plans` where `is_public`) |
| `/signup` (+ Clerk's sub-steps such as `/signup/verify-email-address`) | Everyone | Clerk sign-up form |
| `/login` (+ Clerk's sub-steps such as "forgot password" and the new-device check) | Everyone | Clerk login form |
| `/auth/continue` | Logged-in | Runs after every login/sign-up: copies name + email from Clerk into `profiles`, checks disabled accounts, opens the right page (§7) |
| `/account-disabled` | Everyone (meaningful when logged in) | Explanation + Log out button |
| `/onboarding` | Logged-in | Create an organization, or see pending invitations |
| `/select-organization` | Logged-in with 2+ memberships | Choose an organization |
| `/invite/[token]` | Everyone | Invitation landing page |
| `/organization-suspended` | Logged-in member of a suspended org | Explanation |
| `/app/[orgSlug]/...` | Active member of that organization | The organization panels (`07-panels.md`) |
| `/app/[orgSlug]/profile` | Any member | My profile (phone here; name, email, password in Clerk's account menu) |
| `/platform/...` | PLATFORM_ADMIN | Platform panel |

## 2. Sign-up

1. Person opens `/signup` (Clerk form): email + password (or "Continue with Google" if switched on in the Clerk dashboard).
2. Clerk checks the password rules (set in the Clerk dashboard to match D-35) and whether the email is already used (Clerk shows its own safe messages).
3. Clerk emails a **6-digit verification code**; the account cannot be used until the email is verified.
4. Clerk sends the person to `/auth/continue` → our server copies **name + email from Clerk's server** (never from the browser) into `profiles` using the admin client (`03-architecture.md` §4.1 use #1) → opens the right page (§7).
5. **Open signup** (D-36). Turning sign-ups off (`signups_enabled`) is done in the Clerk dashboard ("Restrictions" → sign-up mode) and by our onboarding check.

## 3. Login, new-device check, password reset

- `/login` (Clerk form): email → password. Wrong details → Clerk's generic message.
- **New device:** Clerk may ask for an email code when someone logs in from a new browser ("client trust") — extra protection against stolen passwords.
- **Forgot password:** inside the Clerk login form ("Forgot password?") → code by email → new password. No pages of our own are needed.
- After login → `/auth/continue` (§7). If Clerk sends the person straight back to the page they wanted instead, that page's own check (`requireUser` / `requireMembership`) creates the profile if it is missing.

## 4. Logout

The Clerk account menu (`UserButton`) has "Sign out"; `/account-disabled` has a Log out button (`SignOutButton`). After logout → `/`.

## 5. Session management

- Clerk keeps the session in secure cookies and refreshes it; `src/proxy.ts` runs `clerkMiddleware()` on every request.
- **Which pages need a login is checked inside each page/layout on the server** (Clerk's recommended approach; route lists in the proxy are deprecated). Server code uses `auth()` / `currentUser()` from `@clerk/nextjs/server`, which verify the token.
- The Supabase server client passes `(await auth()).getToken()` to Supabase on every request. No token → Supabase treats the request as anonymous → sees nothing.
- The Clerk token must contain `role: "authenticated"` — switched on by activating the **Supabase integration in the Clerk dashboard**. Without it Supabase refuses everything (safe failure; tested 2026-09-23).

## 6. Profile

- **Name, email, password, two-step login:** managed in Clerk's account menu (`UserButton` → "Manage account"). Our copy in `profiles` is refreshed at every login (`/auth/continue`).
- **Phone** (and later other business details): edited on our profile page; stored in `profiles`.
- Shows: my email, my role in this organization, list of my organizations; "Leave this organization" (not OWNER / CLIENT).

## 7. How the user's home page is found after login (flow from brief §1.3)

One server function, planned as `resolveHomePath(user)`, runs on `/auth/continue` (right after every login and sign-up) and when a logged-in person opens `/`:

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

## 8. Protected routes

| Route group | Check |
|---|---|
| Public (`/`, `/pricing`, `/login`, `/signup`, `/invite/*`) | none |
| `/auth/continue`, `/onboarding`, `/select-organization`, `/organization-suspended` | page checks a Clerk login (`requireUser`); not logged in → `/login` |
| `/app/[orgSlug]/**` | layout: `requireMembership(slug, roles)` |
| `/platform/**` | layout: `requirePlatformAdmin()` |

## 9. Account status

| Status | Where | Set by | Effect |
|---|---|---|---|
| Account `active` / `disabled` | `profiles.status` (+ "ban" in Clerk) | PLATFORM_ADMIN only | Disabled: Clerk ban blocks login; `/auth/continue` shows `/account-disabled`; all RLS helpers return false |
| Membership `active` / `disabled` | `memberships.status` | OWNER / ADMIN | No access to that one organization |
| Organization `suspended` | `organizations.status` | PLATFORM_ADMIN | Everybody in it sees `/organization-suspended` |

## 10. Onboarding — creating an organization

1. Verified user with no organization opens `/onboarding`.
2. If there are **pending invitations for their email**, they are listed first with "Accept" buttons (§11).
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

## 11. Invitations

### 11.1 Sending (OWNER / ADMIN)

1. `Team → Invite`: email, role (any except OWNER), and **customer** (required when role = CLIENT; the list shows this organization's customers).
2. Server Action: Zod → `requireMembership(slug, [owner, admin])` → checks:
   - no pending invite for the same email in this organization,
   - the email is not already an **active** member,
   - plan limit for users / clients not reached (from Step 22),
   - the customer belongs to this organization (also enforced by the composite FK).
3. Server creates a long random token (32 random bytes), stores **only its SHA-256 hash** in `invitations.token_hash`, `expires_at = now + 7 days` (D-23).
4. Delivery (D-34):
   - the invite link `NEXT_PUBLIC_SITE_URL/invite/<token>` is shown **once** with a "Copy link" button, so the inviter can send it by WhatsApp,
   - and, when an email provider is configured (D-33), an invitation email is sent from our server with the same link.
   With this choice Supabase's own "invite user" admin feature is **not** used, and admin-client use #2 in `03-architecture.md` is removed.
5. Activity log `invitation.created`.

### 11.2 Resend / cancel

- **Resend**: creates a **new** token (the old link stops working), new 7-day expiry, `send_count + 1`, limited (`16-security-performance-testing.md` S-15).
- **Cancel**: status `cancelled`; the link stops working.

### 11.3 Accepting

1. Person opens `/invite/<token>`.
2. The page calls `get_invitation_preview(token)` (database function that returns **only** organization name, role and a partly hidden email like `a***@gmail.com`, and whether the invite is still valid). Invalid/expired/cancelled → friendly message "This invitation is no longer valid, ask for a new one".
3. Not logged in → buttons "Create account" / "Log in" (both return to this page afterwards; signup pre-fills the email).
4. Logged in → "Accept invitation" button → Server Action → database function `accept_invitation(token)`, which in one transaction checks:
   - token hash matches a `pending` invite that is not expired,
   - the logged-in user's **verified email equals the invited email** (case-insensitive) — so a forwarded link cannot be used by someone else. The email is `profiles.email`, copied from Clerk's server (Clerk only allows verified emails to log in),
   - plan limits,
   - the user is not already an active member (if they are a **disabled** member, the membership is re-enabled with the invited role — D-46),
   then inserts the `memberships` row (with `customer_id` for CLIENT), marks the invite `accepted`, logs `invitation.accepted` and notifies the inviter.
5. Redirect to `/app/<slug>`.

Errors: "This invitation was sent to another email address. Log out and log in with a***@gmail.com", "This invitation has expired", "You are already a member of this organization".

## 12. Organization switcher

- In the header of every panel, a dropdown shows the current organization (logo + name + my role) and my other **active** memberships.
- Choosing one opens `/app/<other-slug>` and stores it in `profiles.last_organization_id` (convenience only).
- PLATFORM_ADMIN also sees a "Platform" entry.
- Also offers "Create new organization" (subject to D-37).

## 13. Email sending

| Email | Sent by | V1 |
|---|---|---|
| Verify email (sign-up), reset password, new-device code | **Clerk** | ✅ |
| Invitation | Our server through the email provider (D-34) | ✅ when provider configured; copy-link always available |
| Notifications by email | — | ❌ (future) |

Clerk's development instance sends emails from Clerk's own address; for production you can set your own sender domain in the Clerk dashboard. The email provider from D-33 is still needed for **invitation** emails.

## 14. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-33 | Email provider for **invitation** emails (login emails are sent by Clerk since D-62) | **Resend** (alternatives: Brevo, Amazon SES, Postmark). | Easy setup, free tier enough to start, simple API. Needs a domain you own for sending. |
| D-34 | How invitations are delivered | **Copy-link (for WhatsApp) always + email through our provider once D-33 is set up.** Do not use Supabase's admin "invite user" feature. | Works from day one even without email setup; avoids using the secret key for invites. |
| D-35 | Password rules | **At least 8 characters with at least one letter and one number** — set in the Clerk dashboard (Clerk also blocks known leaked passwords). | Balance between security and ease for non-technical users. |
| D-36 | Who can sign up and create an organization? | **Open signup** with a free trial; PLATFORM_ADMIN can switch signups off. | Needed to get customers without manual work; the switch protects against abuse. |
| D-37 | How many organizations can one user own? | **3** (PLATFORM_ADMIN can raise it for a person). | Stops people creating endless free trials; real multi-business owners are rare. |
| D-38 | Two-factor login (a code from a phone app) | **Not in V1.** V2: optional for everyone, required for PLATFORM_ADMIN first. | Adds setup and support work; V1 users are few and known. |
| D-39 | Changing email address | **Done in Clerk's account menu** (Clerk verifies the new address); our copy updates at the next login. | Came for free with Clerk (D-62). |
| D-45 | Profile photos | **Not in V1** — show initials. | Saves a storage bucket and policies; purely cosmetic. |
| D-46 | Inviting someone who is a disabled member | **Accepting re-enables their membership** with the new role. | Natural way to bring someone back without duplicate rows. |
| D-62 | Login provider | **Clerk** for sign-up/login/password reset/email checks; **Supabase** for database, files and RLS (third-party auth). Decided by you on 2026-09-23. | Ready-made, polished login screens and Google login; security rules stay in our database. |

Referenced: D-12 (currency), D-23 (invite expiry).
