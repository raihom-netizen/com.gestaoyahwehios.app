"use strict";
/**
 * Política única de acesso ao painel — espelha `auth_gate_member_active.dart` (Flutter).
 * Usar em getUserProfile, syncMemberRoleClaims, membroSessionSync, repairMyChurchBinding, etc.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.memberStatusRaw = memberStatusRaw;
exports.memberDocIsPending = memberDocIsPending;
exports.memberDocIsExplicitlyInactive = memberDocIsExplicitlyInactive;
exports.memberDocIsActive = memberDocIsActive;
exports.memberDocHasPrivilegedRole = memberDocHasPrivilegedRole;
exports.resolveMemberPanelAccess = resolveMemberPanelAccess;
function memberStatusRaw(data) {
    if (!data)
        return "";
    return String(data.STATUS ?? data.status ?? "")
        .trim()
        .toLowerCase();
}
function memberDocIsPending(data) {
    return memberStatusRaw(data) === "pendente";
}
function memberDocIsExplicitlyInactive(data) {
    const status = memberStatusRaw(data);
    return (status === "pendente" ||
        status === "reprovado" ||
        status === "inativo" ||
        status === "inativa" ||
        status === "desativado" ||
        status === "desativada");
}
/** Ficha membro permite painel (default vazio = ativo, igual lista Membros). */
function memberDocIsActive(data) {
    if (!data || Object.keys(data).length === 0)
        return false;
    if (memberDocIsExplicitlyInactive(data))
        return false;
    const status = memberStatusRaw(data);
    if (status === "ativo" || status.includes("ativo"))
        return true;
    if (data.ativo === true || data.active === true)
        return true;
    if (status === "")
        return true;
    return false;
}
const PRIVILEGED_ROLE_KEYS = new Set([
    "adm",
    "admin",
    "administrador",
    "administradora",
    "gestor",
    "master",
    "pastor",
    "lider",
    "líder",
]);
function memberDocHasPrivilegedRole(data) {
    if (!data)
        return false;
    const funcoes = data.FUNCOES ?? data.funcoes;
    if (Array.isArray(funcoes)) {
        for (const f of funcoes) {
            const fk = String(f ?? "").trim().toLowerCase();
            if (PRIVILEGED_ROLE_KEYS.has(fk))
                return true;
        }
    }
    for (const key of ["CARGO", "cargo", "FUNCAO", "funcao", "role", "ROLE"]) {
        const cargo = String(data[key] ?? "")
            .trim()
            .toLowerCase();
        if (cargo && PRIVILEGED_ROLE_KEYS.has(cargo))
            return true;
    }
    return false;
}
function resolveMemberPanelAccess(input) {
    const memberData = input.memberData ?? null;
    const memberStatusPending = memberDocIsPending(memberData);
    if (memberStatusPending) {
        return { active: false, memberStatusPending: true };
    }
    let active = input.userAtivo === true ||
        input.userActive === true ||
        input.claimsActive === true;
    if (memberDocIsActive(memberData))
        active = true;
    if (input.isProductMaster)
        active = true;
    const roleNorm = String(input.role ?? "").trim().toLowerCase();
    if (PRIVILEGED_ROLE_KEYS.has(roleNorm))
        active = true;
    if (memberDocHasPrivilegedRole(memberData))
        active = true;
    if (memberDocIsExplicitlyInactive(memberData)) {
        active = false;
    }
    return { active, memberStatusPending: false };
}
//# sourceMappingURL=memberAccessPolicy.js.map