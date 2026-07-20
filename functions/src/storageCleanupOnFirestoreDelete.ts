/**
 * Remove objetos do Storage quando o documento Firestore correspondente é apagado.
 * Complementa o cliente — reforço no servidor (padrão Controle Total: gravar/excluir rápido e limpo).
 *
 * Cobre: membros, chat, eventos, avisos, património, financeiro, fornecedor_compromissos.
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

function collectStoragePaths(data: Record<string, unknown> | undefined): string[] {
  if (!data) return [];
  const keys = [
    "storagePath",
    "comprovanteStoragePath",
    "photoStoragePath",
    "fotoPath",
    "thumbnailStoragePath",
    "thumbPath",
    "thumbStoragePath",
    "bannerStoragePath",
    "capaStoragePath",
  ] as const;
  const paths = new Set<string>();
  for (const key of keys) {
    const p = String(data[key] || "").trim();
    if (p && !p.startsWith("http")) paths.add(p);
  }
  for (let i = 1; i <= 8; i++) {
    const padded = String(i).padStart(2, "0");
    for (const k of [`foto${padded}Path`, `foto${i}Path`, `gallery${i}Path`]) {
      const p = String(data[k] || "").trim();
      if (p && !p.startsWith("http")) paths.add(p);
    }
  }
  return [...paths];
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

/** Chat igreja: ao apagar mensagem (ex.: «para todos»), remove ficheiro em `storagePath`. */
export const onIgrejaChatMessageDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/chats/{threadId}/messages/{msgId}")
  .onDelete(async (snap) => {
    const d = snap.data() as Record<string, unknown> | undefined;
    const paths = new Set(collectStoragePaths(d));
    const main = String(d?.storagePath || "").trim();
    if (main) {
      const guess = main.replace(/\.[^./]+$/, "_thumb.webp");
      if (guess !== main) paths.add(guess);
    }
    for (const path of paths) {
      await deleteIfExists(path);
    }
  });

/** Evento do mural: pasta canónica eventos/{postId}. */
export const onIgrejaNoticiaDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/eventos/{postId}")
  .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId as string);
    const postId = safeSeg(ctx.params.postId as string);
    if (!tenantId || !postId) return;
    await deleteByPrefix(`igrejas/${tenantId}/eventos/${postId}`);
  });

/** Aviso do mural: pasta canónica avisos/{postId}. */
export const onIgrejaAvisoDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{postId}")
  .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId as string);
    const postId = safeSeg(ctx.params.postId as string);
    if (!tenantId || !postId) return;
    await deleteByPrefix(`igrejas/${tenantId}/avisos/${postId}`);
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

/**
 * Financeiro: apaga comprovante no Storage (path canónico + legado).
 * Espelha o padrão CT de limpeza ao excluir lançamento.
 */
export const onIgrejaFinanceDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/finance/{docId}")
  .onDelete(async (snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId as string);
    const docId = safeSeg(ctx.params.docId as string);
    if (!tenantId || !docId) return;
    const d = snap.data() as Record<string, unknown> | undefined;
    for (const path of collectStoragePaths(d)) {
      await deleteIfExists(path);
    }
    const base = `igrejas/${tenantId}/financeiro`;
    for (const ext of ["jpg", "jpeg", "png", "webp", "pdf"]) {
      await deleteIfExists(`${base}/comprovantes_receitas/${docId}_comprovante.${ext}`);
      await deleteIfExists(`${base}/comprovantes_despesas/${docId}_comprovante.${ext}`);
      await deleteIfExists(`${base}/transferencias/${docId}_comprovante.${ext}`);
    }
    try {
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({
        prefix: `${base}/`,
        maxResults: 200,
      });
      const hits = files.filter((f) => {
        const name = f.name || "";
        return (
          name.includes(`/${docId}.`) ||
          name.includes(`/${docId}_`) ||
          name.endsWith(`/${docId}`)
        );
      });
      await Promise.all(
        hits.map((f) => f.delete({ ignoreNotFound: true }).catch(() => undefined)),
      );
    } catch (e) {
      functions.logger.warn(`storageCleanup finance list ${docId}`, e);
    }
  });

/**
 * Fornecedor compromisso: comprovante em
 * `fornecedores/{fid}/compromissos/{cid}_comprovante.*`
 */
export const onIgrejaFornecedorCompromissoDeleteCleanupStorage = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/fornecedor_compromissos/{docId}")
  .onDelete(async (snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId as string);
    const docId = safeSeg(ctx.params.docId as string);
    if (!tenantId || !docId) return;
    const d = snap.data() as Record<string, unknown> | undefined;
    for (const path of collectStoragePaths(d)) {
      await deleteIfExists(path);
    }
    const fid = safeSeg(String(d?.fornecedorId || d?.fornecedorDocId || ""));
    if (fid) {
      const base = `igrejas/${tenantId}/fornecedores/${fid}/compromissos/${docId}_comprovante`;
      for (const ext of ["jpg", "jpeg", "png", "webp", "pdf"]) {
        await deleteIfExists(`${base}.${ext}`);
      }
    }
  });
