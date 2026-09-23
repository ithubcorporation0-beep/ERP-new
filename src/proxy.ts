import { clerkMiddleware } from "@clerk/nextjs/server";
import { NextResponse, type NextFetchEvent, type NextRequest } from "next/server";
import { isClerkConfigured } from "@/lib/env";

// Next.js 16 "proxy" (called middleware in older versions): runs before each request.
// Clerk keeps the login session fresh here. Which pages need a login — and which role —
// is checked inside each page and layout on the server (Clerk's recommended approach and
// our plan, docs/prp/03-architecture.md §2.2), and again by the database (RLS).
const clerk = clerkMiddleware({ signInUrl: "/login", signUpUrl: "/signup" });

export default function proxy(request: NextRequest, event: NextFetchEvent) {
  // Until the Clerk keys are added (e.g. in Vercel), public pages keep working.
  if (!isClerkConfigured()) return NextResponse.next();
  return clerk(request, event);
}

export const config = {
  matcher: [
    // Every page except Next.js build files and static files (images, fonts, …).
    "/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)",
    // Always run for API routes.
    "/(api|trpc)(.*)",
    // Clerk's own helper address.
    "/__clerk/:path*",
  ],
};
