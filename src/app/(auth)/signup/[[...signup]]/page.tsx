import type { Metadata } from "next";
import { SignUp } from "@clerk/nextjs";
import { LoginNotReady } from "@/components/auth/login-not-ready";
import { isClerkConfigured } from "@/lib/env";

export const metadata: Metadata = { title: "Sign up" };

// Clerk's sign-up form. Clerk checks the email address (sends a code) before the
// account can be used. Afterwards the person goes to /auth/continue.
export default function SignupPage() {
  if (!isClerkConfigured()) return <LoginNotReady />;
  return (
    <SignUp
      path="/signup"
      signInUrl="/login"
      fallbackRedirectUrl="/auth/continue"
      signInFallbackRedirectUrl="/auth/continue"
    />
  );
}
