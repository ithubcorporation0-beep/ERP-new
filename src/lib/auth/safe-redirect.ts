// Only allow redirects to pages on THIS website (a path like "/app/x").
// Blocks "open redirect" tricks such as ?next=https://evil.example or ?next=//evil.example.
export function safeNextPath(next: unknown, fallback = "/"): string {
  if (typeof next !== "string") return fallback;
  const value = next.trim();
  if (!value.startsWith("/")) return fallback;
  if (value.startsWith("//") || value.startsWith("/\\")) return fallback;
  if (/[\u0000-\u001f]/.test(value)) return fallback;
  return value;
}
