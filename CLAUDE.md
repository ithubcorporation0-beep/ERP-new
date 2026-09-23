# CLAUDE.md — Rules for Claude Code in this project

Claude Code: read and follow these rules in EVERY session.

## About me
- I am a vibe coder, not an expert programmer. Never assume I know programming concepts.
- Explain things in simple English. When you use a technical word, explain it in one short sentence.

## Project
- Multi-tenant SaaS business management software. Full brief: `docs/MASTER_PROMPT.md`. Approved plan: `docs/prp/`.
- Stack (fixed): Next.js App Router + TypeScript + Tailwind + shadcn/ui, Supabase (Postgres, Auth, Storage, RLS), GitHub, Vercel.
- Before any architecture change: explain why, wait for my OK, then record it in `docs/DECISIONS.md`.

## How we work
1. You create and edit files yourself. Do not ask me to copy-paste code into files unless there is no other way.
2. Never write incomplete code ("rest of code here", "TODO: implement").
3. Keep each step small. Finish and test one phase before starting the next.
4. At the end of every step: run `npm run lint` and `npm run build` and fix errors before saying "done".
5. At the end of every phase: give me a numbered manual test checklist (what to click, what I should see).
6. Anything I must do by hand (Supabase dashboard, Vercel, GitHub, copying keys): write a block titled **ACTION REQUIRED FROM ME** with exact clicks and exact values. Menu names in dashboards can change — describe what to look for if unsure.
7. Give exact commands. Run safe commands yourself. ALWAYS ask me before commands that affect production or are hard to undo (`supabase db push` to production, `git push --force`, deleting files/data, `vercel --prod`).
8. Never rewrite or "clean up" unrelated working code.
9. When there is an error: diagnose first, explain the cause in plain words, then fix only what is needed.
10. Ask me questions only when a missing decision really affects architecture or functionality. Otherwise choose sensibly and record it in `docs/DECISIONS.md`.
11. Do not add npm packages without telling me what each one is for.
12. After each completed step: update `docs/PROJECT_STATUS.md` (what is done) and `docs/TODO.md` (what is left), then make a git commit with a clear message.

## Security (never break these)
- Never use fake credentials. Never invent keys.
- Never put secrets in code. Secrets live only in `.env.local` (local) and Vercel Environment Variables. `.env.local` must be in `.gitignore`.
- `SUPABASE_SECRET_KEY` is server-only: never in client components, never in a `NEXT_PUBLIC_` variable, never logged.
- Never disable RLS or weaken a policy to "make it work".
- Every business table has `organization_id`; every query and every RLS policy is scoped to the user's organization membership.
- Roles come only from the `memberships` / `platform_admins` tables — never from `user_metadata`.
- Validate every form and server action on the server with Zod. Never trust IDs, prices or totals sent from the browser.
- Money: `numeric(12,2)`, calculated on the server/database.
- Never log passwords, tokens or API keys (including in audit logs).

## Database
- All changes go through migration files in `supabase/migrations/` (created with the Supabase CLI), committed to git.
- Never edit a migration that has already been applied — make a new one.
- Never change the database silently: tell me what the migration does in plain words before applying it.
- Every new table: RLS enabled + policies in the same migration + indexes on `organization_id` and foreign keys.
