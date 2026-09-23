import { createBrowserClient } from "@supabase/ssr";
import { requireSupabasePublicEnv } from "@/lib/env";

// Supabase client for code that runs in the browser (Client Components).
// Uses only the public publishable key; database access is limited by RLS.
// In V1 it is used only for login-related events, not for loading business data.
export function createClient() {
  const { url, publishableKey } = requireSupabasePublicEnv();
  return createBrowserClient(url, publishableKey);
}
