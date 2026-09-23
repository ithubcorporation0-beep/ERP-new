// Public, non-secret settings used across the site.
// The product name is not decided yet (decision D-52), so a working name is used
// until NEXT_PUBLIC_APP_NAME is set in .env.local and in Vercel.
export const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME?.trim() || "Business Manager";

export const APP_DESCRIPTION =
  "Customers, projects, invoices, payments and expenses for your business — in one secure place.";
