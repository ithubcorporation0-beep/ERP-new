import type { Metadata } from "next";
import { connection } from "next/server";
import { getSupabasePublicEnv } from "@/lib/env";
import { createAdminClient } from "@/lib/supabase/admin";

// TEMPORARY check page (Step 7). Shows only pass/fail — never any key or data.
// Remove before launch (docs/prp/17-deployment.md §8).
export const metadata: Metadata = {
  title: "Health",
  robots: { index: false, follow: false },
};

type Check = { label: string; ok: boolean; detail: string };

async function runChecks(): Promise<Check[]> {
  const env = getSupabasePublicEnv();
  const hasSecret = Boolean(process.env.SUPABASE_SECRET_KEY?.trim());
  const hasClerk =
    Boolean(process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY?.trim()) &&
    Boolean(process.env.CLERK_SECRET_KEY?.trim());

  const checks: Check[] = [
    {
      label: "Public settings present",
      ok: Boolean(env),
      detail: env
        ? "NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY are set."
        : "Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (see .env.example).",
    },
    {
      label: "Clerk keys present",
      ok: hasClerk,
      detail: hasClerk
        ? "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY and CLERK_SECRET_KEY are set."
        : "Add NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY and CLERK_SECRET_KEY (see .env.example). Login will not work on Vercel without them.",
    },
    {
      label: "Secret key present (server only)",
      ok: hasSecret,
      detail: hasSecret
        ? "SUPABASE_SECRET_KEY is set."
        : "Add SUPABASE_SECRET_KEY to .env.local / Vercel. Never give it the NEXT_PUBLIC_ prefix.",
    },
  ];

  if (!env) return checks;

  // 1. Can we reach Supabase with the publishable key?
  try {
    const res = await fetch(`${env.url}/auth/v1/settings`, {
      headers: { apikey: env.publishableKey },
      cache: "no-store",
    });
    checks.push({
      label: "Supabase reachable with the publishable key",
      ok: res.ok,
      detail: res.ok
        ? "Project URL and publishable key are accepted."
        : `Supabase answered with status ${res.status}. Check the URL and the publishable key.`,
    });
  } catch {
    checks.push({
      label: "Supabase reachable with the publishable key",
      ok: false,
      detail: "Could not reach the project URL. Check NEXT_PUBLIC_SUPABASE_URL.",
    });
  }

  // 2. Is the secret key valid? (read-only call, result not shown)
  if (hasSecret) {
    try {
      const admin = createAdminClient();
      const { error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1 });
      checks.push({
        label: "Secret key accepted",
        ok: !error,
        detail: error ? "Supabase refused the secret key. Copy it again from Project Settings → API Keys." : "OK.",
      });
    } catch {
      checks.push({
        label: "Secret key accepted",
        ok: false,
        detail: "Could not check the secret key.",
      });
    }
  }

  return checks;
}

export default async function HealthPage() {
  await connection(); // always check live, never from a cached copy
  const checks = await runChecks();
  const allOk = checks.every((c) => c.ok);

  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-6 px-4 py-12">
      <h1 className="text-2xl font-semibold">
        {allOk ? "✅ Supabase and Clerk connected" : "❌ Not fully connected yet"}
      </h1>
      <ul className="flex flex-col gap-3">
        {checks.map((c) => (
          <li key={c.label} className="rounded-lg border p-4">
            <p className="font-medium">
              {c.ok ? "✅" : "❌"} {c.label}
            </p>
            <p className="text-sm text-muted-foreground">{c.detail}</p>
          </li>
        ))}
      </ul>
      <p className="text-xs text-muted-foreground">
        Temporary test page. It never shows keys or data.
      </p>
    </main>
  );
}
