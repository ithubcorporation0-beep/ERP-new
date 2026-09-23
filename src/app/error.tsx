"use client";

import { Button } from "@/components/ui/button";

// Shown when a page crashes. Never shows technical details to the user;
// the error code (digest) matches the entry in the server logs.
export default function ErrorPage({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 px-4 py-20 text-center">
      <h1 className="text-2xl font-semibold">Something went wrong</h1>
      <p className="max-w-md text-muted-foreground">
        Please try again. If the problem continues, contact support.
      </p>
      {error.digest ? (
        <p className="text-xs text-muted-foreground">Error code: {error.digest}</p>
      ) : null}
      <Button onClick={() => retry()}>Try again</Button>
    </main>
  );
}
