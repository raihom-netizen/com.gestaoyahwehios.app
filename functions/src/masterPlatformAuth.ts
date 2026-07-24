/** Alinhado a AppConstants + firestore.rules → isPlatformOperator / isAdminPanel. */

export const PLATFORM_MASTER_EMAILS = [
  'raihom@gmail.com',
  'isabellecardoso@gmail.com',
  'isabelle.cardoso@gmail.com',
] as const;

/** UIDs Auth conhecidos dos operadores SaaS (escudo Painel Master). */
export const PLATFORM_MASTER_UIDS = [
  'O0qRLmLER2hwBFqvlzqSdtAUC3D3', // raihom@gmail.com
  'PljAYp6FBuWlGNl69Q2vnRp6gZh2', // isabellecardoso@gmail.com
] as const;

export function isPlatformMasterEmail(email: unknown): boolean {
  const e = String(email ?? '').trim().toLowerCase();
  return (PLATFORM_MASTER_EMAILS as readonly string[]).includes(e);
}

export function isPlatformMasterUid(uid: unknown): boolean {
  const u = String(uid ?? '').trim();
  return (PLATFORM_MASTER_UIDS as readonly string[]).includes(u);
}

/** Token Auth + UID opcional — operador SaaS (não confundir com ADM local da igreja). */
export function isPlatformOperatorToken(
  token: Record<string, unknown> | undefined,
  uid?: string,
): boolean {
  if (isPlatformMasterUid(uid)) return true;
  if (!token) return false;
  if (isPlatformMasterEmail(token.email)) return true;
  const role = String(token.role ?? token.ROLE ?? '').toUpperCase();
  // Só MASTER de plataforma nos claims — ADM/ADMIN da igreja NÃO são SaaS.
  return role === 'MASTER';
}
