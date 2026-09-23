import type { Metadata } from "next";
import { SignIn } from "@clerk/nextjs";

export const metadata: Metadata = { title: "Log in" };

// Clerk's login form (email + password, "forgot password", email codes).
// After login the person goes to /auth/continue, which saves their profile and
// decides which page to open.
export default function LoginPage() {
  return (
    <SignIn
      path="/login"
      signUpUrl="/signup"
      fallbackRedirectUrl="/auth/continue"
      signUpFallbackRedirectUrl="/auth/continue"
    />
  );
}
