import Link from "next/link";
import { APP_NAME } from "@/lib/site";

// Shared layout for /login and /signup: app name on top, Clerk's form centred below.
export default function AuthLayout({ children }: LayoutProps<"/">) {
  return (
    <div className="flex flex-1 flex-col items-center gap-8 px-4 py-10 sm:py-16">
      <Link href="/" className="text-lg font-semibold">
        {APP_NAME}
      </Link>
      {children}
    </div>
  );
}
