# ERP-new — multi-tenant business management SaaS

One website that many businesses can sign up for. Each business (an "organization") manages its customers, projects, tasks, invoices, payments, expenses and documents, and only ever sees its own data.

- Rules for Claude Code: [`CLAUDE.md`](CLAUDE.md)
- Project brief: [`docs/MASTER_PROMPT.md`](docs/MASTER_PROMPT.md)
- Approved plan (PRP): [`docs/prp/`](docs/prp/)
- Build steps: [`docs/BUILD_ORDER.md`](docs/BUILD_ORDER.md)
- Where we are: [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) · what is left: [`docs/TODO.md`](docs/TODO.md) · decisions: [`docs/DECISIONS.md`](docs/DECISIONS.md)

## Tech

Next.js 16 (App Router, TypeScript, `src/`), Tailwind CSS 4, shadcn/ui, Supabase (from Step 7), Vercel.

## Run it on your computer

Needs Node.js 20.9 or newer.

```bash
npm install        # first time only: downloads the packages
npm run dev        # starts the site at http://localhost:3000
```

Other commands:

```bash
npm run lint       # checks the code for mistakes
npm run build      # builds the production version (same as Vercel does)
```

Settings and keys go in `.env.local` (copy `.env.example`). `.env.local` is never committed.
