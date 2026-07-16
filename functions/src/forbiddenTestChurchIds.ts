/**
 * IDs / slugs de igrejas de teste — nunca recriar nem provisionar.
 * Apagar no Console só a raiz deixa subcoleções «fantasma»; jobs de migrate
 * recriavam o doc. Estes IDs ficam bloqueados de forma permanente.
 */
export const FORBIDDEN_TEST_CHURCH_IDS: ReadonlySet<string> = new Set([
  "igreja_de_teste",
  "igreja_de_teste_1",
  "igreja_de_teste_2",
  "igreja_de_teste_3",
  "teste_apple",
  "igreja_teste",
  "igreja-teste",
]);

/** Nomes que slugificam para IDs de teste (onboarding / Master). */
export const FORBIDDEN_TEST_CHURCH_NAME_SLUGS: ReadonlySet<string> = new Set([
  "igreja_de_teste",
  "teste_apple",
  "igreja_teste",
  "igreja_teste_apple",
]);

export function isForbiddenTestChurchId(id: string): boolean {
  const raw = String(id || "").trim().toLowerCase();
  if (!raw) return false;
  if (FORBIDDEN_TEST_CHURCH_IDS.has(raw)) return true;
  // Variantes numeradas: igreja_de_teste_4, teste_apple_1, …
  if (/^igreja_de_teste(_\d+)?$/.test(raw)) return true;
  if (/^teste_apple(_\d+)?$/.test(raw)) return true;
  if (/^igreja_teste(_\d+)?$/.test(raw)) return true;
  return false;
}

export function assertNotForbiddenTestChurchId(id: string, context = "church"): void {
  if (isForbiddenTestChurchId(id)) {
    throw new Error(
      `${context}: id/slug de teste reservado «${id}» — use outro nome (produção).`,
    );
  }
}
