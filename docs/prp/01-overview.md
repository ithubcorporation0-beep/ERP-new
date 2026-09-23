# 01 — Overview

> Part of the PRP (Product Requirements Plan). The PRP is the full written plan we build from.
> Role names, table names and decision numbers (D-xx) are the same in every PRP file.

---

## 1. What the software is

An online **business management software** that many small and medium businesses can use at the same time, each with its own private space. It helps a business manage:

- its **customers**,
- the **projects** it does for those customers and the **tasks** inside each project,
- its **services and products** (a price list),
- **invoices**, **payments** received and **expenses** paid,
- **documents** (files) attached to all of the above,
- its **team** (who works there and what each person may do).

It is sold as **SaaS** (Software as a Service: people use it in a web browser and pay a subscription; nobody installs anything).

## 2. Who uses it

| Who | What they do in the software |
|---|---|
| **The platform owner (me)** — role `PLATFORM_ADMIN` | Runs the SaaS itself: sees which businesses signed up, their plan and status, activates or suspends them, manages plans and announcements. |
| **Business owner** — role `OWNER` | Signs up, creates the business space, controls everything in it including the subscription. |
| **Business staff** — roles `ADMIN`, `MANAGER`, `ACCOUNTANT`, `EMPLOYEE` | Do the daily work: customers, projects, tasks, invoices, payments, expenses. Each sees only what their role allows. |
| **The business's own customers** — role `CLIENT` | Log in to see their own projects, invoices, payments and documents. They never see other customers. |

Full details per role: `02-roles-permissions.md`.

## 3. What problem it solves

Small businesses (example: a marble shop, a contractor, an agency) usually track work on paper, in WhatsApp chats and Excel files. That causes:

- lost track of who owes money (unpaid invoices),
- no clear view of what each employee is working on,
- duplicate or missing invoice numbers,
- customers calling to ask "what is the status?" or "how much do I still owe?",
- files scattered across phones.

The software puts all of this in one place, with the right access for each person, and lets customers check their own status online.

## 4. The SaaS model: platform vs organizations

```
                    ┌──────────────────────────────────────────┐
                    │  PLATFORM  (one website, one database)   │
                    │  run by PLATFORM_ADMIN (me)              │
                    └──────────────────────────────────────────┘
                         │                │                 │
              ┌──────────┘                │                 └──────────┐
     Organization A              Organization B               Organization C
     (e.g. Wajid Marble)         (e.g. an agency)             (…)
     OWNER, ADMIN, staff,        OWNER, staff, clients        …
     clients, own data           own data
```

- **Organization** (also called **tenant**): one business that signed up. Everything a business creates (customers, invoices, files…) belongs to exactly one organization.
- **Multi-tenant**: many organizations share the same website and the same database, but each one only ever sees its own data. This separation is called **tenant isolation** and is the most important security rule of the project.
- **Membership**: the link between a person (user account) and an organization, with a role. One person can be a member of several organizations with a different role in each (example: an accountant working for two businesses).
- **Plan / subscription**: each organization is on a plan (trial, basic, pro…). In V1 payment for the plan is collected **manually** (bank transfer / JazzCash / Easypaisa) and the platform admin activates it. Details: `12-billing-subscriptions.md`.

## 5. Main objectives

1. **Tenant isolation first.** Organization A can never see Organization B's data, even if someone changes an ID in the URL or calls the database directly. Enforced in the database itself (Row Level Security — database rules that decide which rows each user may see).
2. **Right access for every role.** Each person sees and changes only what their role allows.
3. **Correct money.** Invoice numbers never duplicate; totals, balances and statuses are calculated by the server/database, never trusted from the browser.
4. **Simple to use** on a computer and on a phone.
5. **Easy to run** for a single platform owner: manual billing, few moving parts, low cost at the start.
6. **Built step by step**, deployed early, tested at every step.

## 6. Core functionality (Version 1)

| Area | What it does |
|---|---|
| Sign up & login | Email + password accounts, email verification, password reset, account disabled page. |
| Onboarding | New user creates an organization (name, short web name called *slug*, currency, timezone) and becomes its OWNER. |
| Team & invitations | Owner/Admin invite people by email with a role; change role; disable members; transfer ownership. |
| Organization switcher | People in several organizations choose which one to work in. |
| Customers | Customer list with contact details; link a CLIENT login to a customer. |
| Projects & tasks | Projects per customer; tasks with status, priority, due date and one assigned person; comments on tasks. |
| Services/products | A price list used to fill invoice lines quickly. |
| Invoices | Draft → issue with a unique number per organization → payments → paid. Printable view. |
| Payments | Record payments against an invoice; reverse a wrong payment (never silently delete it). |
| Expenses | Record business expenses by category, optionally linked to a project. |
| Documents | Upload files to customers, projects, tasks, invoices, expenses; private storage; organization logo. |
| Notifications | In-app bell: task assigned, invoice created, payment recorded, etc. |
| Dashboards & reports | A dashboard per role; money and work reports calculated in the database. |
| Activity log | Who changed what and when (Owner/Admin can read it). |
| Platform admin panel | Organizations list, suspend/activate, plans, manual subscription activation, announcements. |

## 7. System boundaries — what the software does NOT do (V1)

- **Not full accounting.** No double-entry bookkeeping, general ledger, balance sheet, bank reconciliation or tax filing. (It can export data for an accountant later.)
- **No payroll / HR** (salaries, attendance, leave).
- **No inventory / stock control.** Products have a price, but stock quantities are not tracked (D-19).
- **No online payment collection** from the business's customers, and no automatic card billing for subscriptions (manual billing in V1).
- **No tax rules built in.** The software does not decide any tax rate; the business enters its own (D-10).
- **No email marketing, no WhatsApp/SMS** messages in V1.
- **No public API** for other software to connect to.
- **No offline mode** and **no mobile app** (the website works on phones).
- **No AI features** in V1.

## 8. Version 1 scope vs postponed features

| Feature | V1 | Later (V2 / future) |
|---|---|---|
| Path-based URLs `/app/[orgSlug]/…` | ✅ | Subdomains `slug.mysoftware.com` (D-04) |
| Fixed roles (7 roles) | ✅ | Custom roles per organization |
| One currency per organization | ✅ | Multi-currency invoices (D-12) |
| Manual subscription billing | ✅ | Automatic payment gateway |
| In-app notifications | ✅ | Email / WhatsApp / SMS notifications |
| Built-in Supabase email (testing only) | ✅ dev | Custom SMTP (required before real customers — provider D-33) |
| Tasks with one assignee | ✅ | Several assignees, sub-tasks, time tracking |
| Customer primary contact on the customer record | ✅ | Several contacts per customer (D-16) |
| Payment linked to one invoice | ✅ | Advance payments, one payment split over many invoices, credit notes (D-14) |
| Expense recording by Owner/Admin/Accountant | ✅ | Employee expense claims with approval (D-20) |
| Project budget | ❌ | Budget and profitability per project (D-18) |
| English interface | ✅ | Urdu / other languages (D-26) |
| Reports on screen + CSV export (D-55) | ✅ | Scheduled/emailed reports |
| — | — | Recurring invoices, quotes/estimates, PDF emailing, client portal chat, stock control, AI assistant |

## 9. Decisions for this file (answered 2026-09-23 — "use recommendation")

All decisions are collected and grouped in `19-decisions-required.md` (Step 4). Raised or referenced here:

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-04 | Subdomains per organization in later versions? | Keep path-based URLs in V1; revisit after launch. | Subdomains need wildcard DNS and more complex login cookies; not needed to prove the product. |
| D-26 | Interface language | English only in V1. | Translating every screen doubles text work; add Urdu once screens are stable. |

Other decisions referenced above (D-10, D-12, D-14, D-16, D-18, D-19, D-20) are explained in `02-roles-permissions.md` and `04-database.md`.
