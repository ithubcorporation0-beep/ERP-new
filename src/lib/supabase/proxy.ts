import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getSupabasePublicEnv } from "@/lib/env";

// Pages that need a logged-in user. This is only a first, fast filter:
// the real permission checks happen again in every page and in the database (RLS).
const PROTECTED_PREFIXES = [
  "/app",
  "/platform",
  "/onboarding",
  "/select-organization",
  "/verify-email",
  "/account-disabled",
  "/organization-suspended",
];

function isProtected(pathname: string) {
  return PROTECTED_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}

// Runs before every page request (called from src/proxy.ts):
// 1. refreshes the Supabase login session and writes updated cookies,
// 2. sends logged-out visitors of protected pages to /login.
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const env = getSupabasePublicEnv();
  if (!env) {
    // Supabase is not configured yet (e.g. variables not added in Vercel).
    // Public pages keep working; /health explains what is missing.
    return response;
  }

  const supabase = createServerClient(env.url, env.publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
        // "Do not cache" headers, so one person's login cookie is never served to someone else.
        Object.entries(headers).forEach(([key, value]) => response.headers.set(key, value));
      },
    },
  });

  // Do not run other code between creating the client and this call:
  // it verifies the login token and refreshes it when needed.
  const { data } = await supabase.auth.getClaims();
  const isLoggedIn = Boolean(data?.claims);

  if (!isLoggedIn && isProtected(request.nextUrl.pathname)) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.search = "";
    loginUrl.searchParams.set("next", request.nextUrl.pathname);
    const redirect = NextResponse.redirect(loginUrl);
    // Keep any refreshed cookies on the redirect response.
    response.cookies.getAll().forEach((cookie) => redirect.cookies.set(cookie));
    return redirect;
  }

  return response;
}
