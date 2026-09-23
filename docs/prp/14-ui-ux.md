# 14 — UI / UX

> **UI** (user interface) = how screens look. **UX** (user experience) = how easy and pleasant they are to use.
> We use **Tailwind CSS** (styling with small ready-made class names) and **shadcn/ui** (a set of good-looking, accessible components — buttons, forms, dialogs — copied into our project so we fully control them).

---

## 1. Design style

- **Clean, calm, business-like.** White/light-grey background, one brand colour for actions, lots of spacing, no decoration that doesn't help.
- **Same layout in every panel** (Owner, Manager, Employee, Client, Platform) — only the menu items change. Learn once, use everywhere.
- **Numbers first.** Money and dates are right-aligned in tables, easy to scan.
- **Plain English labels**, short sentences, no technical words in the interface.

## 2. Colour system

Colours are defined once as **design tokens** (named colours such as `primary`, `muted`, `destructive`) in the global CSS, following shadcn/ui's system. Components only use token names, so the whole look can change in one place.

| Token | Use | Default |
|---|---|---|
| `primary` | Main buttons, links, active menu item | Neutral blue (final brand colour D-52) |
| `background` / `foreground` | Page background / main text | White / near-black |
| `muted` | Secondary text, table headers, empty states | Grey |
| `border` | Lines, inputs | Light grey |
| `destructive` | Delete / void / reverse buttons, errors | Red |
| `success` | Paid, completed, success toasts | Green |
| `warning` | Overdue, trial ending, read-only banner | Amber |

Status badges use these consistently everywhere:

| Status | Colour |
|---|---|
| draft, planned, todo | grey |
| sent, active, in_progress | blue |
| partially_paid, on_hold, blocked, overdue, trialing | amber |
| paid, completed, done | green |
| void, cancelled, reversed, disabled, suspended, expired | red/grey (strikethrough for void) |

**Dark mode:** **light mode only in V1** (D-51) (the token system makes dark mode a small later change).
All text/background pairs meet **WCAG AA contrast** (a readability standard: at least 4.5 : 1 for normal text).

## 3. Typography

- One sans-serif font: **Geist** (comes with the new Next.js template) or **Inter** — loaded with Next.js's built-in font loader (no extra requests).
- Sizes: page title 24px semibold, section title 18px semibold, body 14–16px, small/help text 12–13px.
- Numbers in tables use tabular figures (all digits the same width) so columns line up.

## 4. Spacing and layout

- Tailwind spacing scale (multiples of 4px). Page padding 16px on phones, 24–32px on desktop. Cards have 16–24px inside padding.
- **App shell** (all panels):

```
┌──────────────────────────────────────────────────────────────┐
│ [Logo] Org name ▾ (switcher)          🔔 3    (AB) User ▾      │  header
├───────────────┬──────────────────────────────────────────────┤
│ Dashboard     │  [banner: announcement / trial / read-only]    │
│ Customers     │  Page title                   [Main action]    │
│ Projects      │  Filters / search                              │
│ Tasks         │  Content (table, form, cards)                  │
│ …             │                                                │
│               │  Pagination                                    │
└───────────────┴──────────────────────────────────────────────┘
      sidebar (role-based menu)
```

- Header: organization **logo + name** (from `organizations`), organization switcher, notification bell, user menu (profile, log out).
- Platform panel uses the same shell with a "Platform" label and platform menu.
- Breadcrumbs on detail pages ("Invoices / INV-2026-0012").

## 5. Components (shadcn/ui)

| Element | Rules |
|---|---|
| **Buttons** | One primary button per screen area (e.g. "Save", "Issue invoice"); secondary = outline; dangerous = red and always behind a confirm dialog. Buttons show a spinner and are disabled while saving (no double submits) |
| **Forms** | Label above each field; required fields marked; help text under tricky fields; errors in red under the field (from the server's Zod result) plus a summary toast; dates with a date picker; money fields with 2 decimals and currency shown; forms keep what the user typed if the server returns an error |
| **Tables** | Header row, zebra or hover rows, right-aligned numbers, status badges, row click opens detail, actions in a "⋯" menu; server-side pagination below ("Showing 26–50 of 312") |
| **Cards** | Dashboard numbers (big number, label, small comparison), detail sections |
| **Modals (dialogs)** | Short tasks only (record payment, invite member, confirm void). Long forms get their own page |
| **Confirm dialogs** | For void, reverse, disable, archive, delete, transfer ownership: explain what happens, require a reason where the PRP says so; transfer ownership and organization deletion require typing the organization name |
| **Toasts** | Top-right on desktop, bottom on phones; success auto-hides after 4 s; errors stay until closed |
| **Tabs** | Detail pages (customer: Overview / Projects / Invoices / Payments / Documents) |
| **Empty states** | Icon + one sentence + main action ("No invoices yet. Create your first invoice") |
| **Loading states** | Skeletons (grey placeholder shapes) while a page loads (`loading.tsx`), spinner on buttons |
| **Error states** | Friendly page "Something went wrong. Try again." with a retry button (`error.tsx`); "Not found" page for missing/forbidden records; "No access" page for forbidden modules. Never show technical details |
| **Banners** | Announcement, trial ending, read-only (expired), invitation pending — one line, coloured by level |

## 6. Mobile responsiveness

- Designed to work from **360px** wide phones up.
- **Sidebar → drawer:** below 1024px the sidebar hides behind a ☰ menu button and slides in (shadcn "Sheet").
- Tables: on phones show the 2–3 most important columns; the rest appear on the detail page. Where a full table is needed (invoice lines) it scrolls sideways inside its box, never the whole page.
- Forms become one column; buttons full width at the bottom.
- Touch targets at least 44×44px.
- Employees mainly use phones: "My Tasks" and status change must be easy with one thumb; photo upload opens the camera.

## 7. Accessibility

- shadcn/ui components are built on Radix (accessible building blocks): keyboard navigation, focus handling and screen-reader labels work out of the box.
- Every input has a visible label; icons-only buttons have text for screen readers.
- Visible focus ring on everything clickable; logical tab order.
- Colour is never the only signal (badges have text; errors have text).
- Page `<title>` per page ("Invoices — Wajid Marble"); correct heading order; `lang="en"`.

## 8. Printing

The invoice print view and payment receipt use a print stylesheet: A4, black on white, no menus/buttons, logo and organization details at top, totals block at bottom-right, "DRAFT"/"VOID" watermarks (`09-finance.md` §10).

## 9. Formatting

- Money: organization currency, 2 decimals, thousands separators (`Rs 1,250,000.00`).
- Dates: `23 Sep 2026`; date + time: `23 Sep 2026, 3:45 pm` in the organization timezone.
- Relative times in notifications and logs ("2 hours ago"), with the exact time on hover.

## 10. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-51 | Dark mode | **Light mode only in V1.** | Halves visual testing; tokens make it easy to add later. |

Referenced: D-52 (brand name and colour).
