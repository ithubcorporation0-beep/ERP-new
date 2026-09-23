import Link from "next/link";
import { Button } from "@/components/ui/button";

// Shown on /login and /signup while the Clerk keys are not added yet.
export function LoginNotReady() {
  return (
    <div className="flex max-w-md flex-col items-center gap-4 text-center">
      <h1 className="text-2xl font-semibold">Login is being set up</h1>
      <p className="text-muted-foreground">
        Sign-up and login will be available here soon. Please check back later.
      </p>
      <Button asChild variant="outline">
        <Link href="/">Back to the home page</Link>
      </Button>
    </div>
  );
}
