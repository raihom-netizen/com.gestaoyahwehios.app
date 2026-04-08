/**
 * Remove objetos do Storage quando o documento Firestore correspondente é apagado.
 * Complementa o cliente (ex.: deleteMemberRelatedFiles): reforço no servidor.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

function safeSeg(s: string): string {
  return String(s || "")
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, "_");
}

async function deleteByPrefix(prefix: string): Promise<void> {
  const p = prefix.replace(/\/+$/, "");
  if (!p) return;
  const bucket = admin.storage().bucket();
  try {
    await bucket.deleteFiles({ prefix: `${p}/` });
  } catch (e) {
    functions.logger.warn(`storageCleanup: prefix ${p}/`, e);
  }
}

async function deleteIfExists(path: string): Promise<void> {
  if (!path) return;
  try {
    await admin.storage().bucket().file(path).delete({ ignoreNotFound: true });
  } catch (e) {
    functions.logger.warn(`storageCleanup: file ${path}`, e);
  }
}

/** Pasta por membro + ficheiros planos legados `{id}.jpg`. */
export const onIgrejaMembroDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/membros/{memberId}")
  .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId as string);
    const memberId = safeSeg(ctx.params.memberId as string);
    if (!tenantId || !memberId) return;
    const base = `igrejas/${tenantId}/membros/${memberId}`;
    await deleteByPrefix(base);
    for (const ext of ["jpg", "jpeg", "png", "webp"]) {
      await deleteIfExists(`${base}.${ext}`);
    }
    for (const suf of ["_thumb", "_card", "_full", "_gestor"]) {
      await deleteIfExists(`${base}${suf}.jpg`);
    }
    await deleteIfExists(`${base}_assinatura.png`);
    await deleteIfExists(`${base}_digital.png`);
  });

/** Post do mural (evento ou aviso): pastas canónicas + prefixo legado noticias/. */
export const onIgrejaNoticiaDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/noticias/{postId}")
  .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId as string);
    const postId = safeSeg(ctx.params.postId as string);
    if (!tenantId || !postId) return;
    await deleteByPrefix(`igrejas/${tenantId}/eventos/${postId}`);
    await deleteByPrefix(`igrejas/${tenantId}/avisos/${postId}`);
    await deleteByPrefix(`igrejas/${tenantId}/noticias/${postId}`);
  });

/** Património: pasta `patrimonio/{id}/` + ficheiros planos `{id}_{slot}.jpg` (legado). */
export const onIgrejaPatrimonioDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/patrimonio/{itemId}")
  .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId as string);
    const itemId = safeSeg(ctx.params.itemId as string);
    if (!tenantId || !itemId) return;
    await deleteByPrefix(`igrejas/${tenantId}/patrimonio/${itemId}`);
    for (let slot = 0; slot <= 4; slot++) {
      const base = `igrejas/${tenantId}/patrimonio/${itemId}_${slot}`;
      await deleteIfExists(`${base}.jpg`);
      for (const suf of ["_thumb", "_card", "_full"]) {
        await deleteIfExists(`${base}${suf}.jpg`);
      }
    }
  });
