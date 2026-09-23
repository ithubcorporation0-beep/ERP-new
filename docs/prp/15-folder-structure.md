# 15 — Folder Structure

> In the Next.js **App Router**, every folder inside `src/app` becomes part of a web address, and a `page.tsx` file inside it is the page.
> A folder in **(round brackets)** is a **route group**: it groups pages that share a layout but does **not** appear in the address.
> A folder in **[square brackets]** is a **dynamic segment**: it matches any value, e.g. `[orgSlug]` matches `wajid-marble`.

Folders are created only when the step that needs them starts (Step 5 creates just the basics).

---

## 1. Tree

```
ERP-new/
├── CLAUDE.md                      Rules for Claude Code
├── README.md                      Short project intro + how to run it
├── .env.example                   Names of environment variables (no values)
├── .env.local                     Real values on your computer (never committed)
├── .gitignore                     Files git must ignore (.env*.local, node_modules, .next …)
├── package.json                   npm packages and scripts (dev, build, lint, test)
├── next.config.ts                 Next.js settings (security headers, images)
├── tsconfig.json                  TypeScript settings
├── components.json                shadcn/ui settings
├── eslint.config.mjs              Lint rules (code-style checker)
├── vitest.config.ts               Unit test settings
│
├── docs/
│   ├── MASTER_PROMPT.md           Project brief
│   ├── BUILD_ORDER.md             The 24 build steps
│   ├── PROJECT_STATUS.md          What is done
│   ├── TODO.md                    What is left
│   ├── DECISIONS.md               Decision log
│   └── prp/                       The plan (01–19)
│
├── public/                        Static files served as-is (favicon, default images)
│
├── supabase/
│   ├── config.toml                Supabase CLI settings
│   ├── migrations/                Database changes, one timestamped SQL file each (never edited after applying)
│   ├── tests/                     pgTAP SQL tests (RLS, tenant isolation, money)
│   └── seed.sql                   Demo data for the dev project only (fake orgs/users for testing)
│
├── tests/
│   ├── unit/                      Vitest tests for TypeScript logic (Zod schemas, formatting, permission maps)
│   └── e2e/                       Browser tests (optional, D-61)
│
└── src/
    ├── proxy.ts                   Session refresh + logged-out redirect (named middleware.ts on older Next.js)
    │
    ├── app/
    │   ├── layout.tsx             Root layout: <html>, font, toasts
    │   ├── globals.css            Tailwind + colour tokens
    │   ├── not-found.tsx          Global "Not found" page
    │   ├── error.tsx              Global friendly error page
    │   │
    │   ├── (public)/              Public marketing pages (no login)
    │   │   ├── page.tsx           Home  → /
    │   │   └── pricing/page.tsx   → /pricing
    │   │
    │   ├── (auth)/                Login-related pages sharing a centred card layout
    │   │   ├── layout.tsx
    │   │   ├── login/page.tsx
    │   │   ├── signup/page.tsx
    │   │   ├── forgot-password/page.tsx
    │   │   ├── reset-password/page.tsx
    │   │   └── verify-email/page.tsx
    │   │
    │   ├── auth/                  Route Handlers (no pages)
    │   │   ├── confirm/route.ts   Email link handler (verification, reset)
    │   │   └── signout/route.ts   Log out (POST)
    │   │
    │   ├── (account)/             Logged-in pages outside any organization
    │   │   ├── layout.tsx
    │   │   ├── onboarding/page.tsx
    │   │   ├── select-organization/page.tsx
    │   │   ├── account-disabled/page.tsx
    │   │   └── organization-suspended/page.tsx
    │   │
    │   ├── invite/[token]/page.tsx   Invitation landing page
    │   │
    │   ├── app/[orgSlug]/         Organization panels → /app/wajid-marble/...
    │   │   ├── layout.tsx         requireMembership + app shell (sidebar, header)
    │   │   ├── loading.tsx        Skeleton while loading
    │   │   ├── error.tsx          Friendly error inside the shell
    │   │   ├── page.tsx           Dashboard (per role)
    │   │   ├── team/ …            customers/ …   projects/ …   tasks/ …
    │   │   ├── services/ …        invoices/ …    payments/ …   expenses/ …
    │   │   ├── documents/ …       reports/ …     notifications/ …
    │   │   ├── activity/ …        settings/ …    billing/ …    profile/ …
    │   │   └── (each module: page.tsx list, new/page.tsx, [id]/page.tsx, [id]/edit/page.tsx as in 07-panels.md)
    │   │
    │   ├── platform/              Platform admin panel → /platform/...
    │   │   ├── layout.tsx         requirePlatformAdmin + shell
    │   │   ├── page.tsx
    │   │   └── organizations/ plans/ subscriptions/ users/ announcements/ settings/ audit-log/ profile/
    │   │
    │   └── health/page.tsx        Temporary "Supabase connected" check (Step 7, removed before launch)
    │
    ├── components/
    │   ├── ui/                    shadcn/ui components (button, input, dialog, table, sheet …)
    │   ├── layout/                App shell: sidebar, header, org switcher, user menu, mobile drawer, banners
    │   └── shared/                Reusable pieces: data table, pagination, search box, status badge, money, date, empty state, confirm dialog, file upload
    │
    ├── features/                  One folder per business module, everything for that module together
    │   ├── auth/                  (each module folder contains:)
    │   ├── organizations/         actions.ts     Server Actions (Zod → requireMembership → Supabase)
    │   ├── members/               queries.ts     Server-only data loading functions
    │   ├── customers/             schemas.ts     Zod schemas (shared by form and server)
    │   ├── projects/              components/    Forms, tables, detail parts for this module
    │   ├── tasks/
    │   ├── catalog/               (services/products)
    │   ├── invoices/
    │   ├── payments/
    │   ├── expenses/
    │   ├── documents/
    │   ├── notifications/
    │   ├── reports/
    │   ├── activity/
    │   └── platform/
    │
    ├── lib/
    │   ├── supabase/
    │   │   ├── client.ts          Browser client (publishable key)
    │   │   ├── server.ts          Server client (user's session cookies)
    │   │   ├── proxy.ts           Session refresh helper used by src/proxy.ts
    │   │   └── admin.ts           Secret-key client — `import 'server-only'` (03-architecture §4.1)
    │   ├── auth/                  requireUser, requireMembership, requirePlatformAdmin, resolveHomePath
    │   ├── permissions.ts         Role → allowed modules/actions map (for menus and server checks; mirrors 02)
    │   ├── env.ts                 Reads and checks environment variables
    │   ├── format.ts              Money and date formatting
    │   ├── errors.ts              Turns database error codes into friendly messages
    │   └── utils.ts               Small helpers (shadcn `cn` etc.)
    │
    └── types/
        └── database.types.ts      Generated from the database by the Supabase CLI (never edited by hand)
```

Note: the folder `src/app/app/` looks odd, but it is correct: the outer `app` is Next.js's folder for pages, the inner `app` makes the address `/app/...`.

## 2. Why "features/" instead of putting everything in `app/`

Page files in `src/app` stay thin (load data, check access, render components). The real logic of each module (actions, queries, schemas, components) lives in `src/features/<module>/`, so everything about invoices is in one place and is easy to find, test and change.

## 3. Planned npm packages

Rule 11 of `CLAUDE.md`: every package is announced before it is installed. Planned so far (exact versions checked at install time):

| Package | What it is for | Step |
|---|---|---|
| `next`, `react`, `react-dom`, `typescript`, `tailwindcss`, `eslint` | The base app (installed by `create-next-app`) | 5 |
| shadcn/ui CLI (`npx shadcn`) + the packages it adds (`radix-ui` parts, `class-variance-authority`, `clsx`, `tailwind-merge`, `lucide-react` icons) | UI components | 5 |
| `sonner` | Toast pop-ups (shadcn's toast component) | 5/9 |
| `@supabase/ssr`, `@supabase/supabase-js` | Talking to Supabase with cookie sessions | 7 |
| `server-only` | Makes the build fail if server code is imported into the browser | 7 |
| `supabase` (CLI, run with `npx`, dev dependency) | Migrations, type generation, tests | 7 |
| `zod` | Server-side validation | 9 |
| `react-hook-form`, `@hookform/resolvers` | Comfortable forms that use the same Zod schemas (shadcn Form) | 9 |
| `date-fns` + `date-fns-tz` (or `@date-fns/tz`) | Date maths and timezone display | 13 |
| `vitest` (dev) | Unit tests | 15 |
| `recharts` (via shadcn charts) | Dashboard charts | 20 |
| `@playwright/test` (dev, optional) | Browser tests (D-61) | 23 |

Not planned: state-management libraries, ORMs (database helper libraries), CSS frameworks other than Tailwind, `@supabase/auth-helpers-*` (deprecated).

## 4. Decisions raised in this file

None new. Referenced: D-61 (browser tests, in `16-security-performance-testing.md`).
