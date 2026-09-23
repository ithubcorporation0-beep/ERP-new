import type { Metadata } from "next";
import { ClerkProvider } from "@clerk/nextjs";
import { shadcn } from "@clerk/ui/themes";
import { Geist, Geist_Mono } from "next/font/google";
import { isClerkConfigured } from "@/lib/env";
import { APP_DESCRIPTION, APP_NAME } from "@/lib/site";
import "./globals.css";

// "--font-sans" is the name the shadcn/ui styles in globals.css expect.
const geistSans = Geist({
  variable: "--font-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: {
    default: APP_NAME,
    template: `%s — ${APP_NAME}`,
  },
  description: APP_DESCRIPTION,
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="flex min-h-full flex-col">
        {/* Clerk handles login; it must sit inside <body>. The shadcn theme makes its forms match our design.
            Without Clerk keys (not set up yet) the site still opens, without login. */}
        {isClerkConfigured() ? (
          <ClerkProvider
            appearance={{ theme: shadcn }}
            signInUrl="/login"
            signUpUrl="/signup"
            afterSignOutUrl="/"
          >
            {children}
          </ClerkProvider>
        ) : (
          children
        )}
      </body>
    </html>
  );
}
