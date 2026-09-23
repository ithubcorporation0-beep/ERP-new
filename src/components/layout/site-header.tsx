import Link from "next/link";
import { Show, SignInButton, SignUpButton, UserButton } from "@clerk/nextjs";
import { Button } from "@/components/ui/button";
import { isClerkConfigured } from "@/lib/env";
import { APP_NAME } from "@/lib/site";

// Header for public pages: "Log in" / "Sign up" when logged out,
// the Clerk account menu (profile, security, log out) when logged in.
export function SiteHeader() {
  return (
    <header className="border-b">
      <div className="mx-auto flex h-16 w-full max-w-5xl items-center justify-between gap-4 px-4 sm:px-6">
        <Link href="/" className="text-lg font-semibold">
          {APP_NAME}
        </Link>
        {isClerkConfigured() ? (
          <div className="flex items-center gap-2">
            <Show when="signed-out">
              <SignInButton>
                <Button variant="ghost">Log in</Button>
              </SignInButton>
              <SignUpButton>
                <Button>Sign up</Button>
              </SignUpButton>
            </Show>
            <Show when="signed-in">
              <UserButton />
            </Show>
          </div>
        ) : (
          <span className="text-sm text-muted-foreground">Login is being set up</span>
        )}
      </div>
    </header>
  );
}
