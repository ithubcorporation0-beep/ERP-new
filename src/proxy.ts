import { clerkMiddleware } from "@clerk/nextjs/server";

// Next.js 16 "proxy" (called middleware in older versions): runs before each request.
// Clerk keeps the login session fresh here. Which pages need a login — and which role —
// is checked inside each page and layout on the server (Clerk's recommended approach and
// our plan, docs/prp/03-architecture.md §2.2), and again by the database (RLS).
export default clerkMiddleware({ signInUrl: "/login", signUpUrl: "/signup" });

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
