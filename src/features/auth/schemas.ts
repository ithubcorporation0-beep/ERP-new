import { z } from "zod";

// Shared validation rules for all login forms (checked on the server — never trusted from the browser).

export const emailSchema = z
  .string({ error: "Please enter your email." })
  .trim()
  .toLowerCase()
  .min(1, "Please enter your email.")
  .max(254, "This email is too long.")
  .pipe(z.email("Please enter a valid email."));

// D-35: at least 8 characters with at least one letter and one number.
// 72 is the maximum length Supabase Auth accepts.
export const newPasswordSchema = z
  .string({ error: "Please choose a password." })
  .min(8, "Password must be at least 8 characters.")
  .max(72, "Password must be 72 characters or fewer.")
  .regex(/[A-Za-z]/, "Password must include at least one letter.")
  .regex(/[0-9]/, "Password must include at least one number.");

export const signupSchema = z.object({
  fullName: z
    .string({ error: "Please enter your name." })
    .trim()
    .min(1, "Please enter your name.")
    .max(100, "Name must be 100 characters or fewer."),
  email: emailSchema,
  password: newPasswordSchema,
  acceptTerms: z.literal("on", { error: "Please accept the terms to continue." }),
});

export const loginSchema = z.object({
  email: emailSchema,
  password: z
    .string({ error: "Please enter your password." })
    .min(1, "Please enter your password.")
    .max(72, "Email or password is incorrect."),
  next: z.string().max(500).optional(),
});

export const emailOnlySchema = z.object({
  email: emailSchema,
});

export const resetPasswordSchema = z
  .object({
    password: newPasswordSchema,
    confirmPassword: z.string({ error: "Please type the password again." }),
  })
  .refine((data) => data.password === data.confirmPassword, {
    path: ["confirmPassword"],
    message: "The two passwords do not match.",
  });

// What every auth form action returns to the page.
export type AuthFormState = {
  status: "idle" | "error" | "success";
  message?: string;
  fieldErrors?: Partial<Record<string, string[]>>;
  values?: Record<string, string>;
};

export const initialAuthFormState: AuthFormState = { status: "idle" };
