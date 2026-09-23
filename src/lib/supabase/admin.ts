import "server-only";
import { createClient } from "@supabase/supabase-js";
import { requireSupabasePublicEnv } from "@/lib/env";
import type { Database } from "@/types/database.types";

// DANGER: this client uses the SECRET key and ignores all Row Level Security rules.
// "server-only" above makes the build fail if browser code ever imports this file.
//
// Allowed uses only (docs/prp/03-architecture.md §4.1), each AFTER an explicit
// permission check in code and with an activity-log entry:
//   1. Copy the logged-in user's name and email from Clerk into `profiles` (D-62) —
//      the details come from Clerk's server, never from the browser.
//   2. PLATFORM_ADMIN permanently deletes an organization's data and files (D-24).
// (Temporary: the /health page uses it once to check that the secret key is valid.)
export function createAdminClient() {
  const { url } = requireSupabasePublicEnv();
  const secretKey = process.env.SUPABASE_SECRET_KEY?.trim();
  if (!secretKey) {
    throw new Error(
      "Missing SUPABASE_SECRET_KEY. Add it to .env.local and to Vercel (server-only, never NEXT_PUBLIC_).",
    );
  }

  return createClient<Database>(url, secretKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}
