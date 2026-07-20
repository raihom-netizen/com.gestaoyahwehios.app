/**
 * Cloud Functions — anexos padronizados (WISDOMAPP → GESTAOYAHWEH).
 * Web instável: Admin SDK grava Storage + Firestore sem conflito com snapshots().
 */
import * as functions from "firebase-functions/v1";
import { admin, fs, storageBucket } from "./adminDb";
import { resolveTenantIdForCallable, userCanAccessTenant } from "./tenantCallableResolve";
import { resolvePublicChurchIdFromInput } from "./panelPublicSiteCache";

const CF_DELETE = "__DELETE__";
const MAX_FINANCE_BYTES = 15 * 1024 * 1024;
const ALLOWED_FEED_COLLECTIONS = new Set([
  "avisos",
  "eventos",
  "patrimonio",
  "finance",
  "membros",
  "fornecedores",
  "fornecedor_compromissos",
  "chats",
  "agenda",
  "visitantes",
  "departamentos",
  "cargos",
]);

/** Coleções que o Admin SDK pode apagar em lote (Web rápida — padrão CT). */
const ALLOWED_ADMIN_DELETE_COLLECTIONS = new Set([
  "avisos",
  "eventos",
  "patrimonio",
  "finance",
  "membros",
  "fornecedores",
  "fornecedor_compromissos",
  "agenda",
  "visitantes",
  "pedidosOracao",
]);

function resolveTenantDocRef(
  churchId: string,
  collection: string,
  docId: string,
  subCollection?: string,
  subDocId?: string,
) {
  let ref = fs()
    .collection("igrejas")
    .doc(churchId)
    .collection(collection)
    .doc(docId);
  const subCol = (subCollection || "").trim();
  const subId = (subDocId || "").trim();
  if (subCol && subId) {
    ref = ref.collection(subCol).doc(subId);
  }
  return ref;
}

function decodeAdminFirestoreValue(value: unknown): unknown {
  if (value === CF_DELETE) {
    return admin.firestore.FieldValue.delete();
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const o = value as Record<string, unknown>;
    if (typeof o._tsMs === "number" && Number.isFinite(o._tsMs)) {
      return admin.firestore.Timestamp.fromMillis(o._tsMs);
    }
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(o)) {
      out[k] = decodeAdminFirestoreValue(v);
    }
    return out;
  }
  if (Array.isArray(value)) {
    return value.map(decodeAdminFirestoreValue);
  }
  return value;
}

function decodeAdminFirestoreMap(raw: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(raw || {})) {
    out[k] = decodeAdminFirestoreValue(v);
  }
  return out;
}

async function requireChurchAccess(
  context: functions.https.CallableContext,
  churchId: string,
): Promise<{ uid: string; email: string; churchId: string }> {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
  }
  const uid = context.auth.uid;
  const email = String((context.auth.token?.email as string) || "")
    .trim()
    .toLowerCase();
  const tid = String(churchId || "").trim();
  if (!tid) {
    throw new functions.https.HttpsError("invalid-argument", "churchId ausente.");
  }
  const resolved = await resolveTenantIdForCallable(
    { uid, token: context.auth.token as Record<string, unknown> },
    tid,
  );
  if (!resolved || resolved !== tid) {
    throw new functions.https.HttpsError("permission-denied", "Sem acesso a esta igreja.");
  }
  const ok = await userCanAccessTenant(uid, email, tid);
  if (!ok) {
    throw new functions.https.HttpsError("permission-denied", "Sem permissão nesta igreja.");
  }
  return { uid, email, churchId: tid };
}

function extFromMime(mimeType: string, fileName?: string): string {
  const m = String(mimeType || "").toLowerCase();
  if (m.includes("pdf")) return "pdf";
  if (m.includes("png")) return "png";
  if (m.includes("webp")) return "webp";
  const fn = String(fileName || "").toLowerCase();
  if (fn.endsWith(".pdf")) return "pdf";
  if (fn.endsWith(".png")) return "png";
  if (fn.endsWith(".webp")) return "webp";
  return "jpg";
}

function financeComprovantePath(
  churchId: string,
  lancamentoId: string,
  referenceDate?: string,
  ext = "jpg",
): string {
  let ym = referenceDate?.trim() || "";
  if (!/^\d{4}_\d{2}$/.test(ym)) {
    const now = new Date();
    const y = now.getFullYear();
    const mo = String(now.getMonth() + 1).padStart(2, "0");
    ym = `${y}_${mo}`;
  }
  const safeExt = ext.replace(/[^a-z0-9]/gi, "").slice(0, 8) || "jpg";
  return `igrejas/${churchId}/financeiro/${ym}/${lancamentoId}.${safeExt}`;
}

/**
 * Web: base64 → Storage → merge Firestore comprovante* no lançamento finance/.
 * Espelho WISDOMAPP ctUploadReceiptToStorage.
 */
export const gyUploadFinanceComprovante = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data, context) => {
    const body = (data || {}) as Record<string, unknown>;
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const lancamentoId = String(body.lancamentoId || body.docId || "").trim();
    const base64 = String(body.base64 || body.dataBase64 || "").trim();
    const mimeType = String(body.mimeType || "image/jpeg").trim();
    const fileName = String(body.fileName || "comprovante").trim();

    const auth = await requireChurchAccess(context, churchId);
    if (!lancamentoId) {
      throw new functions.https.HttpsError("invalid-argument", "lancamentoId ausente.");
    }
    if (!base64) {
      throw new functions.https.HttpsError("invalid-argument", "base64 ausente.");
    }

    let buffer: Buffer;
    try {
      buffer = Buffer.from(base64, "base64");
    } catch {
      throw new functions.https.HttpsError("invalid-argument", "base64 inválido.");
    }
    if (buffer.length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "Arquivo vazio.");
    }
    if (buffer.length > MAX_FINANCE_BYTES) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `Arquivo grande demais (máx ${MAX_FINANCE_BYTES / (1024 * 1024)} MB).`,
      );
    }
    if (mimeType.toLowerCase().startsWith("video/")) {
      throw new functions.https.HttpsError("invalid-argument", "Vídeo não permitido.");
    }

    const ext = extFromMime(mimeType, fileName);
    const refDate = String(body.referenceYearMonth || body.yearMonth || "").trim();
    const storagePath = financeComprovantePath(
      auth.churchId,
      lancamentoId,
      refDate || undefined,
      ext,
    );

    const contentType =
      ext === "pdf"
        ? "application/pdf"
        : ext === "png"
          ? "image/png"
          : ext === "webp"
            ? "image/webp"
            : "image/jpeg";

    const bucket = storageBucket();
    const file = bucket.file(storagePath);
    const token = fs().collection("_meta").doc().id;
    await file.save(buffer, {
      metadata: {
        contentType,
        cacheControl: "public, max-age=31536000",
        metadata: { firebaseStorageDownloadTokens: token },
      },
      resumable: false,
    });
    const [metadata] = await file.getMetadata();
    if (!metadata?.name) {
      throw new functions.https.HttpsError("internal", "Falha ao confirmar upload Storage.");
    }

    const encoded = encodeURIComponent(storagePath);
    const downloadUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;

    const docRef = fs()
      .collection("igrejas")
      .doc(auth.churchId)
      .collection("finance")
      .doc(lancamentoId);

    const patch = {
      comprovanteUrl: downloadUrl,
      comprovanteLink: downloadUrl,
      comprovanteStoragePath: storagePath,
      comprovanteMimeType: contentType,
      comprovanteFileName: fileName || `comprovante.${ext}`,
      hasComprovante: true,
      comprovanteUploadState: "published",
      comprovanteUploadError: admin.firestore.FieldValue.delete(),
      comprovanteUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await docRef.set(patch, { merge: true });

    return {
      ok: true,
      comprovanteUrl: downloadUrl,
      storagePath,
      mimeType: contentType,
      fileName: patch.comprovanteFileName,
    };
  });

/**
 * Web: upsert documento de feed/patrimônio/finance via Admin SDK.
 * Espelho WISDOMAPP ctAdminUpsertCourseVideo.
 */
export const gyAdminUpsertFeedPost = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (data, context) => {
    const body = (data || {}) as Record<string, unknown>;
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const collection = String(body.collection || body.subcollection || "").trim();
    const docId = String(body.docId || body.id || "").trim();
    const subCollection = String(body.subCollection || body.subcollectionPath || "").trim();
    const subDocId = String(body.subDocId || body.subId || "").trim();
    const rawData = (body.data || {}) as Record<string, unknown>;
    const create = body.create === true;
    const merge = body.merge !== false;
    const useUpdate = body.useUpdate === true;

    const auth = await requireChurchAccess(context, churchId);
    if (!ALLOWED_FEED_COLLECTIONS.has(collection)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `collection inválida: ${collection}`,
      );
    }
    if (!docId) {
      throw new functions.https.HttpsError("invalid-argument", "docId ausente.");
    }
    if (subCollection && !subDocId) {
      throw new functions.https.HttpsError("invalid-argument", "subDocId ausente.");
    }

    const decoded = decodeAdminFirestoreMap(rawData);
    decoded.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    if (create && !useUpdate) {
      decoded.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }

    const docRef = resolveTenantDocRef(
      auth.churchId,
      collection,
      docId,
      subCollection || undefined,
      subDocId || undefined,
    );

    if (useUpdate) {
      await docRef.update(decoded);
    } else if (create && !merge) {
      await docRef.set(decoded);
    } else {
      await docRef.set(decoded, { merge: true });
    }

    return {
      ok: true,
      docId: subDocId || docId,
      path: docRef.path,
    };
  });

/**
 * Web: merge doc raiz `igrejas/{churchId}` via Admin SDK.
 * Espelho WISDOMAPP — evita INTERNAL ASSERTION no Firestore JS ao gravar cadastro.
 */
export const gyAdminUpsertChurchRoot = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (data, context) => {
    const body = (data || {}) as Record<string, unknown>;
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const rawData = (body.data || {}) as Record<string, unknown>;
    const merge = body.merge !== false;

    const auth = await requireChurchAccess(context, churchId);
    const decoded = decodeAdminFirestoreMap(rawData);
    decoded.updatedAt = admin.firestore.FieldValue.serverTimestamp();

    const docRef = fs().collection("igrejas").doc(auth.churchId);
    if (merge) {
      await docRef.set(decoded, { merge: true });
    } else {
      await docRef.set(decoded);
    }

    return { ok: true, path: docRef.path };
  });

/** Exclusão em lote Admin SDK — qualquer módulo do painel (Web rápida, padrão CT). */
export const gyAdminDeleteFeedPosts = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    const body = (data || {}) as Record<string, unknown>;
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const collection = String(body.collection || "avisos").trim();
    const docIds = Array.isArray(body.docIds)
      ? (body.docIds as unknown[]).map((id) => String(id || "").trim()).filter(Boolean)
      : [];

    const auth = await requireChurchAccess(context, churchId);
    if (!ALLOWED_ADMIN_DELETE_COLLECTIONS.has(collection)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `collection inválida para exclusão: ${collection}`,
      );
    }
    if (docIds.length === 0) {
      return { ok: true, deleted: 0 };
    }
    if (docIds.length > 32) {
      throw new functions.https.HttpsError("invalid-argument", "Máximo 32 docs por chamada.");
    }

    const batch = fs().batch();
    for (const id of docIds) {
      const ref = fs()
        .collection("igrejas")
        .doc(auth.churchId)
        .collection(collection)
        .doc(id);
      batch.delete(ref);
    }
    await batch.commit();
    return { ok: true, deleted: docIds.length, collection };
  });

/**
 * Cadastro membro público — Admin SDK (Web-safe, Fase 3 doc mestre).
 * Auth opcional; valida slug/churchId e grava draft em igrejas/{id}/membros.
 */
export const gyPublicMemberSignup = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (data, context) => {
    const body = (data || {}) as Record<string, unknown>;
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const docId = String(body.docId || body.memberId || "").trim();
    const rawData = (body.data || {}) as Record<string, unknown>;

    if (!churchId) {
      throw new functions.https.HttpsError("invalid-argument", "churchId ausente.");
    }
    if (!docId) {
      throw new functions.https.HttpsError("invalid-argument", "docId ausente.");
    }

    const churchSnap = await fs().collection("igrejas").doc(churchId).get();
    if (!churchSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }

    const decoded = decodeAdminFirestoreMap(rawData);
    decoded.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    decoded.createdAt = admin.firestore.FieldValue.serverTimestamp();
    decoded.status = decoded.status || "pendente_aprovacao";
    decoded.publicSignup = true;
    if (context.auth?.uid) {
      decoded.authUid = context.auth.uid;
    }

    const docRef = fs()
      .collection("igrejas")
      .doc(churchId)
      .collection("membros")
      .doc(docId);

    await docRef.set(decoded, { merge: true });
    return { ok: true, docId, path: docRef.path };
  });

function pickPublicString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (v != null && String(v).trim()) return String(v).trim();
  }
  return "";
}

/** Status de cadastro público — visitante anónimo (sem leitura directa de `membros`). */
export const gyPublicSignupStatus = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data) => {
    const body = (data || {}) as Record<string, unknown>;
    const protocolo = String(body.protocolo || body.docId || "").trim();
    if (!protocolo) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "protocolo ausente.",
      );
    }

    const churchId = await resolvePublicChurchIdFromInput(
      body.churchId ?? body.tenantId ?? body.slug,
    );
    if (!churchId) {
      throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }

    const churchSnap = await fs().collection("igrejas").doc(churchId).get();
    if (!churchSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }
    const church = (churchSnap.data() ?? {}) as Record<string, unknown>;
    const churchName =
      pickPublicString(church, ["nome", "name", "NOME_IGREJA", "nomeIgreja"]) ||
      "Igreja";

    const membros = fs()
      .collection("igrejas")
      .doc(churchId)
      .collection("membros");

    let memberSnap = await membros.doc(protocolo).get();
    if (!memberSnap.exists) {
      const legacy = await membros
        .where("legacyMemberDocId", "==", protocolo)
        .limit(1)
        .get();
      if (!legacy.empty) memberSnap = legacy.docs[0];
    }

    if (!memberSnap.exists) {
      return {
        ok: false,
        found: false,
        churchId,
        churchName,
        error: "Cadastro não localizado para o protocolo informado.",
      };
    }

    const member = (memberSnap.data() ?? {}) as Record<string, unknown>;
    if (member.publicSignup !== true) {
      return {
        ok: false,
        found: false,
        churchId,
        churchName,
        error: "Protocolo inválido para acompanhamento público.",
      };
    }

    const nome =
      pickPublicString(member, ["NOME_COMPLETO", "nome", "name"]) || "Membro";
    const status = String(member.status ?? member.STATUS ?? "pendente").trim();

    return {
      ok: true,
      found: true,
      churchId,
      churchName,
      protocolo: memberSnap.id,
      nome,
      status,
    };
  });
