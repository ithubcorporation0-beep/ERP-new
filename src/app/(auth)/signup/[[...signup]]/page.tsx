import type { Metadata } from "next";
import { SignUp } from "@clerk/nextjs";

export const metadata: Metadata = { title: "Sign up" };

// Clerk's sign-up form. Clerk checks the email address (sends a code) before the
// account can be used. Afterwards the person goes to /auth/continue.
export default function SignupPage() {
  return (
    <SignUp
      path="/signup"
      signInUrl="/login"
      fallbackRedirectUrl="/auth/continue"
      signInFallbackRedirectUrl="/auth/continue"
    />
  );
}
