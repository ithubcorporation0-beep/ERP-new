import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/current-user";
import { safeNextPath } from "@/lib/auth/safe-redirect";

// Runs right after every login / sign-up:
// 1. copies the person's name and email from Clerk into our database,
// 2. sends disabled accounts to /account-disabled,
// 3. otherwise opens the next page.
// (Step 10 replaces step 3 with the full rules: organization, platform, onboarding…)
export default async function ContinueAfterLogin(props: PageProps<"/auth/continue">) {
  const searchParams = await props.searchParams;
  const user = await getCurrentUser({ refresh: true });

  if (!user) {
    redirect("/login");
  }
  if (user.status === "disabled") {
    redirect("/account-disabled");
  }
  redirect(safeNextPath(searchParams.next, "/"));
}
