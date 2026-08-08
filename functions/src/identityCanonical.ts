import * as admin from "firebase-admin";

/**
 * Identidade canônica (authUid + cpf + email) para membros/usuários.
 *
 * Padroniza NOVOS cadastros (igrejas atuais e futuras) preenchendo APENAS
 * campos que faltam, copiando de fontes já existentes no próprio documento.
 * Nunca sobrescreve valor existente nem adivinha match contra o Auth.
 * Espelha `scripts/identity_backfill.cjs` (usado no backfill dos dados atuais).
 */

const onlyDigits = (s: unknown): string => String(s ?? "").replace(/\D/g, "");

/** Um id/uid do Firebase Auth (>= 20 chars) que NÃO é um CPF de 11 dígitos. */
const looksUid = (s: unknown): boolean =>
  typeof s === "string" && s.length >= 20 && !/^[0-9]{11}$/.test(s);

/** Patch aditivo para canonizar a identidade de uma ficha `membros/{id}`. */
export function buildCanonicalMemberPatch(
  data: Record<string, unknown>,
  memberId: string,
): Record<string, unknown> {
  const patch: Record<string, unknown> = {};

  // email (minúsculo) <- email || EMAIL (verbatim)
  if (!data.email) {
    const src =
      typeof data.email === "string" && data.email
        ? data.email
        : typeof data.EMAIL === "string"
          ? data.EMAIL
          : "";
    if (src) patch.email = src;
  }

  // cpf (minúsculo, 11 dígitos) <- cpf || CPF || cpfDigits
  if (!data.cpf) {
    const digits = onlyDigits(data.cpf ?? data.CPF ?? data.cpfDigits);
    if (digits.length === 11) patch.cpf = digits;
  }

  // authUid <- authUid || firebaseUid || (docId, se parecer uid)
  if (!data.authUid) {
    const uid =
      typeof data.firebaseUid === "string" && looksUid(data.firebaseUid)
        ? data.firebaseUid
        : looksUid(memberId)
          ? memberId
          : "";
    if (uid) patch.authUid = uid;
  }

  return patch;
}

/** Patch aditivo para `users/{uid}` (raiz): garante authUid = uid. */
export function buildCanonicalRootUserPatch(
  data: Record<string, unknown>,
  userId: string,
): Record<string, unknown> {
  const patch: Record<string, unknown> = {};
  if (!data.authUid && looksUid(userId)) patch.authUid = userId;
  return patch;
}

/** Patch aditivo para `igrejas/{t}/users/{uid}`: authUid = uid + igrejaId = tenant. */
export function buildCanonicalTenantUserPatch(
  data: Record<string, unknown>,
  tenantId: string,
  userId: string,
): Record<string, unknown> {
  const patch: Record<string, unknown> = {};
  if (!data.authUid && looksUid(userId)) patch.authUid = userId;
  if (!data.igrejaId && tenantId) patch.igrejaId = tenantId;
  return patch;
}

/** Aplica o patch canônico (merge) só se houver algo a preencher. */
export async function stampCanonicalMember(
  ref: admin.firestore.DocumentReference,
  data: Record<string, unknown>,
  memberId: string,
): Promise<void> {
  const patch = buildCanonicalMemberPatch(data, memberId);
  if (Object.keys(patch).length) await ref.set(patch, { merge: true });
}
