/**
 * Política única de acesso ao painel — espelha `auth_gate_member_active.dart` (Flutter).
 * Usar em getUserProfile, syncMemberRoleClaims, membroSessionSync, repairMyChurchBinding, etc.
 */

export function memberStatusRaw(data: Record<string, unknown> | null | undefined): string {
  if (!data) return "";
  return String(data.STATUS ?? data.status ?? "")
    .trim()
    .toLowerCase();
}

export function memberDocIsPending(data: Record<string, unknown> | null | undefined): boolean {
  return memberStatusRaw(data) === "pendente";
}

export function memberDocIsExplicitlyInactive(
  data: Record<string, unknown> | null | undefined,
): boolean {
  const status = memberStatusRaw(data);
  return (
    status === "pendente" ||
    status === "reprovado" ||
    status === "inativo" ||
    status === "inativa" ||
    status === "desativado" ||
    status === "desativada"
  );
}

/** Ficha membro permite painel (default vazio = ativo, igual lista Membros). */
export function memberDocIsActive(data: Record<string, unknown> | null | undefined): boolean {
  if (!data || Object.keys(data).length === 0) return false;
  if (memberDocIsExplicitlyInactive(data)) return false;
  const status = memberStatusRaw(data);
  if (status === "ativo" || status.includes("ativo")) return true;
  if (data.ativo === true || data.active === true) return true;
  if (status === "") return true;
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

export function memberDocHasPrivilegedRole(
  data: Record<string, unknown> | null | undefined,
): boolean {
  if (!data) return false;
  const funcoes = data.FUNCOES ?? data.funcoes;
  if (Array.isArray(funcoes)) {
    for (const f of funcoes) {
      const fk = String(f ?? "").trim().toLowerCase();
      if (PRIVILEGED_ROLE_KEYS.has(fk)) return true;
    }
  }
  for (const key of ["CARGO", "cargo", "FUNCAO", "funcao", "role", "ROLE"]) {
    const cargo = String((data as Record<string, unknown>)[key] ?? "")
      .trim()
      .toLowerCase();
    if (cargo && PRIVILEGED_ROLE_KEYS.has(cargo)) return true;
  }
  return false;
}

export function resolveMemberPanelAccess(input: {
  userAtivo?: boolean;
  userActive?: boolean;
  claimsActive?: boolean;
  role?: string;
  memberData?: Record<string, unknown> | null;
  isProductMaster?: boolean;
}): { active: boolean; memberStatusPending: boolean } {
  const memberData = input.memberData ?? null;
  const memberStatusPending = memberDocIsPending(memberData);
  if (memberStatusPending) {
    return { active: false, memberStatusPending: true };
  }

  let active =
    input.userAtivo === true ||
    input.userActive === true ||
    input.claimsActive === true;

  if (memberDocIsActive(memberData)) active = true;
  if (input.isProductMaster) active = true;

  const roleNorm = String(input.role ?? "").trim().toLowerCase();
  if (PRIVILEGED_ROLE_KEYS.has(roleNorm)) active = true;
  if (memberDocHasPrivilegedRole(memberData)) active = true;

  if (memberDocIsExplicitlyInactive(memberData)) {
    active = false;
  }

  return { active, memberStatusPending: false };
}
