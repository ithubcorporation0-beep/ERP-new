import { FolderKanban, ReceiptText, ShieldCheck, Users } from "lucide-react";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { APP_DESCRIPTION, APP_NAME } from "@/lib/site";

const features = [
  {
    icon: Users,
    title: "Customers & team",
    description:
      "Keep every customer in one list and give each team member the right access.",
  },
  {
    icon: FolderKanban,
    title: "Projects & tasks",
    description:
      "Plan work, assign tasks and see what is done, late or waiting.",
  },
  {
    icon: ReceiptText,
    title: "Invoices & payments",
    description:
      "Issue numbered invoices, record payments and always know who still owes you.",
  },
  {
    icon: ShieldCheck,
    title: "Private by design",
    description:
      "Each business only ever sees its own data. Your customers only see their own records.",
  },
];

export default function HomePage() {
  return (
    <div className="flex flex-1 flex-col">
      <header className="border-b">
        <div className="mx-auto flex h-16 w-full max-w-5xl items-center px-4 sm:px-6">
          <span className="text-lg font-semibold">{APP_NAME}</span>
        </div>
      </header>

      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-12 px-4 py-12 sm:px-6 sm:py-20">
        <section className="flex flex-col gap-4 text-center">
          <h1 className="text-3xl font-semibold tracking-tight sm:text-5xl">
            Run your business from one place
          </h1>
          <p className="mx-auto max-w-2xl text-base text-muted-foreground sm:text-lg">
            {APP_DESCRIPTION}
          </p>
          <p className="text-sm text-muted-foreground">
            Sign-up and login are coming soon.
          </p>
        </section>

        <section className="grid gap-4 sm:grid-cols-2">
          {features.map(({ icon: Icon, title, description }) => (
            <Card key={title}>
              <CardHeader>
                <Icon className="mb-2 size-6 text-primary" aria-hidden="true" />
                <CardTitle>{title}</CardTitle>
                <CardDescription>{description}</CardDescription>
              </CardHeader>
            </Card>
          ))}
        </section>
      </main>

      <footer className="border-t">
        <div className="mx-auto w-full max-w-5xl px-4 py-6 text-sm text-muted-foreground sm:px-6">
          © {new Date().getFullYear()} {APP_NAME}
        </div>
      </footer>
    </div>
  );
}
