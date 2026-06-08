import * as admin from "firebase-admin";

/** PNG 1×1 transparente — materializa pastas vazias no bucket (igual ao app). */
const MIN_PLACEHOLDER_PNG = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48,
  0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
  0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78,
  0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/** `igrejas/{tenantId}/configuracoes/logo_igreja.png` (placeholder mínimo se ausente). */
export async function ensureConfiguracoesStorageFolder(
  tenantId: string,
): Promise<{ created: boolean; path: string }> {
  const tid = String(tenantId || "").trim();
  if (!tid) return { created: false, path: "" };
  const bucket = admin.storage().bucket();
  const pngPath = `igrejas/${tid}/configuracoes/logo_igreja.png`;
  const jpgPath = `igrejas/${tid}/configuracoes/logo_igreja.jpg`;
  for (const path of [pngPath, jpgPath]) {
    const file = bucket.file(path);
    const [exists] = await file.exists();
    if (exists) return { created: false, path };
  }
  await bucket.file(pngPath).save(MIN_PLACEHOLDER_PNG, {
    contentType: "image/png",
    resumable: false,
    metadata: { cacheControl: "public,max-age=60" },
  });
  return { created: true, path: pngPath };
}

/** `igrejas/{tenantId}/financeiro/_structure/placeholder.png` */
export async function ensureFinanceiroStorageFolder(
  tenantId: string,
): Promise<{ created: boolean; path: string }> {
  const tid = String(tenantId || "").trim();
  if (!tid) return { created: false, path: "" };
  const path = `igrejas/${tid}/financeiro/_structure/placeholder.png`;
  const bucket = admin.storage().bucket();
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (exists) return { created: false, path };
  await file.save(MIN_PLACEHOLDER_PNG, {
    contentType: "image/png",
    resumable: false,
    metadata: { cacheControl: "public,max-age=60" },
  });
  return { created: true, path };
}
