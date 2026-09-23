import "server-only";
import { auth } from "@clerk/nextjs/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { requireSupabasePublicEnv } from "@/lib/env";
import type { Database } from "@/types/database.types";

// Supabase client for Server Components, Server Actions and Route Handlers.
// Every request carries the logged-in user's Clerk token, which Supabase checks
// ("third-party auth"). So it acts as that user and RLS applies to every query.
// Not logged in → no token → Supabase treats the request as anonymous (sees nothing).
// Create a new client for every request — never share one between requests.
export async function createClient() {
  const { url, publishableKey } = requireSupabasePublicEnv();

  return createSupabaseClient<Database>(url, publishableKey, {
    async accessToken() {
      return (await auth()).getToken();
    },
  });
}
