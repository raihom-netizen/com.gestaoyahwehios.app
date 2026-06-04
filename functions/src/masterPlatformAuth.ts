/** Alinhado a `firestore.rules` → isPlatformOperator / isAdminPanel. */
export function isPlatformOperatorToken(
  token: Record<string, unknown> | undefined,
): boolean {
  if (!token) return false;
  const email = String(token.email ?? "").trim().toLowerCase();
  if (email === "raihom@gmail.com") return true;
  const role = String(token.role ?? token.ROLE ?? "").toUpperCase();
  return role === "MASTER" || role === "ADM" || role === "ADMIN";
}
