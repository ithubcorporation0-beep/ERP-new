import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { requireSupabasePublicEnv } from "@/lib/env";

// Supabase client for Server Components, Server Actions and Route Handlers.
// It acts as the logged-in user (session from cookies), so RLS applies to every query.
// Create a new client for every request — never share one between requests.
export async function createClient() {
  const { url, publishableKey } = requireSupabasePublicEnv();
  const cookieStore = await cookies();

  return createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Server Components cannot set cookies. This is safe to ignore because
          // src/proxy.ts refreshes the session cookies on every request.
        }
      },
    },
  });
}
