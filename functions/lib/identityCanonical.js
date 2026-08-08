"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCanonicalMemberPatch = buildCanonicalMemberPatch;
exports.buildCanonicalRootUserPatch = buildCanonicalRootUserPatch;
exports.buildCanonicalTenantUserPatch = buildCanonicalTenantUserPatch;
exports.stampCanonicalMember = stampCanonicalMember;
/**
 * Identidade canônica (authUid + cpf + email) para membros/usuários.
 *
 * Padroniza NOVOS cadastros (igrejas atuais e futuras) preenchendo APENAS
 * campos que faltam, copiando de fontes já existentes no próprio documento.
 * Nunca sobrescreve valor existente nem adivinha match contra o Auth.
 * Espelha `scripts/identity_backfill.cjs` (usado no backfill dos dados atuais).
 */
const onlyDigits = (s) => String(s ?? "").replace(/\D/g, "");
/** Um id/uid do Firebase Auth (>= 20 chars) que NÃO é um CPF de 11 dígitos. */
const looksUid = (s) => typeof s === "string" && s.length >= 20 && !/^[0-9]{11}$/.test(s);
/** Patch aditivo para canonizar a identidade de uma ficha `membros/{id}`. */
function buildCanonicalMemberPatch(data, memberId) {
    const patch = {};
    // email (minúsculo) <- email || EMAIL (verbatim)
    if (!data.email) {
        const src = typeof data.email === "string" && data.email
            ? data.email
            : typeof data.EMAIL === "string"
                ? data.EMAIL
                : "";
        if (src)
            patch.email = src;
    }
    // cpf (minúsculo, 11 dígitos) <- cpf || CPF || cpfDigits
    if (!data.cpf) {
        const digits = onlyDigits(data.cpf ?? data.CPF ?? data.cpfDigits);
        if (digits.length === 11)
            patch.cpf = digits;
    }
    // authUid <- authUid || firebaseUid || (docId, se parecer uid)
    if (!data.authUid) {
        const uid = typeof data.firebaseUid === "string" && looksUid(data.firebaseUid)
            ? data.firebaseUid
            : looksUid(memberId)
                ? memberId
                : "";
        if (uid)
            patch.authUid = uid;
    }
    return patch;
}
/** Patch aditivo para `users/{uid}` (raiz): garante authUid = uid. */
function buildCanonicalRootUserPatch(data, userId) {
    const patch = {};
    if (!data.authUid && looksUid(userId))
        patch.authUid = userId;
    return patch;
}
/** Patch aditivo para `igrejas/{t}/users/{uid}`: authUid = uid + igrejaId = tenant. */
function buildCanonicalTenantUserPatch(data, tenantId, userId) {
    const patch = {};
    if (!data.authUid && looksUid(userId))
        patch.authUid = userId;
    if (!data.igrejaId && tenantId)
        patch.igrejaId = tenantId;
    return patch;
}
/** Aplica o patch canônico (merge) só se houver algo a preencher. */
async function stampCanonicalMember(ref, data, memberId) {
    const patch = buildCanonicalMemberPatch(data, memberId);
    if (Object.keys(patch).length)
        await ref.set(patch, { merge: true });
}
//# sourceMappingURL=identityCanonical.js.map