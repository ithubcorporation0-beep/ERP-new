// Reads the public Supabase settings from environment variables.
// Values live in .env.local (your computer) and in Vercel → Settings → Environment Variables.
// NEXT_PUBLIC_ values must be read with their full literal names so Next.js can copy them
// into browser code; they are safe to be public. The secret key is read only in
// src/lib/supabase/admin.ts (server-only).

export type SupabasePublicEnv = {
  url: string;
  publishableKey: string;
};

export function getSupabasePublicEnv(): SupabasePublicEnv | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !publishableKey) return null;
  return { url, publishableKey };
}

export function requireSupabasePublicEnv(): SupabasePublicEnv {
  const env = getSupabasePublicEnv();
  if (!env) {
    throw new Error(
      "Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY. " +
        "Add them to .env.local (see .env.example) and to Vercel, then restart or redeploy.",
    );
  }
  return env;
}

// The public address of this website, used in email links (confirm email, reset password).
// Local: NEXT_PUBLIC_SITE_URL=http://localhost:3000. Vercel Preview: left empty, so the
// automatic preview address is used. Production: your real domain.
export function getSiteUrl(): string {
  const configured = process.env.NEXT_PUBLIC_SITE_URL?.trim();
  if (configured) return configured.replace(/\/+$/, "");
  const vercelUrl = process.env.VERCEL_URL?.trim();
  if (vercelUrl) return `https://${vercelUrl}`;
  return "http://localhost:3000";
}
