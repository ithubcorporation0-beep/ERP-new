"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { getSiteUrl } from "@/lib/env";
import { safeNextPath } from "@/lib/auth/safe-redirect";
import { createClient } from "@/lib/supabase/server";
import {
  type AuthFormState,
  emailOnlySchema,
  loginSchema,
  resetPasswordSchema,
  signupSchema,
} from "./schemas";

function fieldErrorsOf(error: z.ZodError): AuthFormState["fieldErrors"] {
  return z.flattenError(error).fieldErrors;
}

function text(formData: FormData, name: string): string | undefined {
  const value = formData.get(name);
  return typeof value === "string" ? value : undefined;
}

// Turn Supabase Auth error codes into plain-English messages. Never reveals whether an
// email has an account, and never shows technical details.
function friendlyAuthError(code: string | undefined, status: number | undefined): string {
  if (status === 429 || code === "over_request_rate_limit" || code === "over_email_send_rate_limit") {
    return "Too many attempts. Please wait a few minutes and try again.";
  }
  if (code === "weak_password") {
    return "Please choose a stronger password (at least 8 characters with letters and numbers).";
  }
  if (code === "signup_disabled") {
    return "New sign-ups are closed at the moment. Please try again later.";
  }
  if (code === "same_password") {
    return "Your new password must be different from your old one.";
  }
  return "Something went wrong. Please try again.";
}

export async function signUp(_prev: AuthFormState, formData: FormData): Promise<AuthFormState> {
  const values = { fullName: text(formData, "fullName") ?? "", email: text(formData, "email") ?? "" };
  const parsed = signupSchema.safeParse({
    fullName: text(formData, "fullName"),
    email: text(formData, "email"),
    password: text(formData, "password"),
    acceptTerms: text(formData, "acceptTerms"),
  });
  if (!parsed.success) {
    return { status: "error", fieldErrors: fieldErrorsOf(parsed.error), values };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email: parsed.data.email,
    password: parsed.data.password,
    options: {
      // Used ONLY to fill profiles.full_name — never for roles.
      data: { full_name: parsed.data.fullName },
      emailRedirectTo: `${getSiteUrl()}/auth/confirm?next=/`,
    },
  });
  if (error) {
    return { status: "error", message: friendlyAuthError(error.code, error.status), values };
  }

  // Same result whether or not the email already had an account (no account guessing).
  redirect(`/verify-email?email=${encodeURIComponent(parsed.data.email)}`);
}

export async function signIn(_prev: AuthFormState, formData: FormData): Promise<AuthFormState> {
  const values = { email: text(formData, "email") ?? "" };
  const parsed = loginSchema.safeParse({
    email: text(formData, "email"),
    password: text(formData, "password"),
    next: text(formData, "next"),
  });
  if (!parsed.success) {
    return { status: "error", fieldErrors: fieldErrorsOf(parsed.error), values };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });

  if (error) {
    if (error.code === "email_not_confirmed") {
      redirect(`/verify-email?email=${encodeURIComponent(parsed.data.email)}&reason=unconfirmed`);
    }
    if (error.status === 429 || error.code === "over_request_rate_limit") {
      return { status: "error", message: friendlyAuthError(error.code, error.status), values };
    }
    return { status: "error", message: "Email or password is incorrect.", values };
  }

  // Disabled accounts see an explanation page (they cannot use any organization anyway).
  const { data: profile } = await supabase
    .from("profiles")
    .select("status")
    .eq("id", data.user.id)
    .maybeSingle();
  if (profile?.status === "disabled") {
    redirect("/account-disabled");
  }

  // Step 10 replaces this with the full "which page to open" rules (organization, platform, …).
  redirect(safeNextPath(parsed.data.next, "/"));
}

export async function requestPasswordReset(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const values = { email: text(formData, "email") ?? "" };
  const parsed = emailOnlySchema.safeParse({ email: text(formData, "email") });
  if (!parsed.success) {
    return { status: "error", fieldErrors: fieldErrorsOf(parsed.error), values };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
    redirectTo: `${getSiteUrl()}/auth/confirm?next=/reset-password`,
  });
  if (error && (error.status === 429 || error.code?.startsWith("over_"))) {
    return { status: "error", message: friendlyAuthError(error.code, error.status), values };
  }

  // Always the same answer, so nobody can find out which emails have accounts.
  return {
    status: "success",
    message: "If an account exists for this email, we have sent a link to reset the password.",
    values,
  };
}

export async function updatePassword(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const parsed = resetPasswordSchema.safeParse({
    password: text(formData, "password"),
    confirmPassword: text(formData, "confirmPassword"),
  });
  if (!parsed.success) {
    return { status: "error", fieldErrors: fieldErrorsOf(parsed.error) };
  }

  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) {
    return {
      status: "error",
      message: "Your reset link has expired. Please ask for a new one.",
    };
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    return { status: "error", message: friendlyAuthError(error.code, error.status) };
  }

  redirect("/?notice=password-updated");
}

export async function resendConfirmation(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const values = { email: text(formData, "email") ?? "" };
  const parsed = emailOnlySchema.safeParse({ email: text(formData, "email") });
  if (!parsed.success) {
    return { status: "error", fieldErrors: fieldErrorsOf(parsed.error), values };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.resend({
    type: "signup",
    email: parsed.data.email,
    options: { emailRedirectTo: `${getSiteUrl()}/auth/confirm?next=/` },
  });
  if (error && (error.status === 429 || error.code?.startsWith("over_"))) {
    return { status: "error", message: friendlyAuthError(error.code, error.status), values };
  }

  return {
    status: "success",
    message: "If this email is waiting for confirmation, we have sent a new link.",
    values,
  };
}
