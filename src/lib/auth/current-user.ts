import "server-only";
import { auth, currentUser } from "@clerk/nextjs/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export type CurrentUser = {
  id: string; // Clerk user id, e.g. "user_2abc…"
  email: string;
  fullName: string;
  status: "active" | "disabled";
};

type ProfileRow = { id: string; email: string; full_name: string; status: string };

function toCurrentUser(row: ProfileRow): CurrentUser {
  return {
    id: row.id,
    email: row.email,
    fullName: row.full_name,
    status: row.status === "disabled" ? "disabled" : "active",
  };
}

// Copies name + email from Clerk into our `profiles` table. The details are fetched
// from Clerk's server with our secret key — never taken from the browser.
// Only name and email are written; status (active/disabled) is never touched here.
async function syncProfileFromClerk(userId: string): Promise<ProfileRow | null> {
  const user = await currentUser();
  if (!user || user.id !== userId) return null;

  const email = (user.primaryEmailAddress?.emailAddress ?? "").trim().toLowerCase();
  const fullName = ([user.firstName, user.lastName].filter(Boolean).join(" ") || user.username || "")
    .trim()
    .slice(0, 100);

  const admin = createAdminClient();
  const { data, error } = await admin
    .from("profiles")
    .upsert({ id: user.id, email, full_name: fullName }, { onConflict: "id" })
    .select("id, email, full_name, status")
    .single();
  if (error) {
    throw new Error("Could not save the user profile.");
  }
  return data;
}

// The logged-in person, or null when nobody is logged in.
// `refresh: true` re-copies name and email from Clerk (used right after login).
export async function getCurrentUser({ refresh = false } = {}): Promise<CurrentUser | null> {
  const { userId } = await auth();
  if (!userId) return null;

  if (!refresh) {
    const supabase = await createClient();
    const { data } = await supabase
      .from("profiles")
      .select("id, email, full_name, status")
      .eq("id", userId)
      .maybeSingle();
    if (data) return toCurrentUser(data);
  }

  const synced = await syncProfileFromClerk(userId);
  return synced ? toCurrentUser(synced) : null;
}
