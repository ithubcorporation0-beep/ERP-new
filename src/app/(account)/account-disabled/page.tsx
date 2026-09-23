import type { Metadata } from "next";
import { SignOutButton } from "@clerk/nextjs";
import { Button } from "@/components/ui/button";
import { isClerkConfigured } from "@/lib/env";

export const metadata: Metadata = { title: "Account disabled" };

export default function AccountDisabledPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 px-4 py-20 text-center">
      <h1 className="text-2xl font-semibold">Your account is disabled</h1>
      <p className="max-w-md text-muted-foreground">
        You cannot use this account at the moment. If you think this is a mistake, please
        contact support.
      </p>
      {isClerkConfigured() ? (
        <SignOutButton redirectUrl="/">
          <Button variant="outline">Log out</Button>
        </SignOutButton>
      ) : null}
    </main>
  );
}
