import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

function pickPhotoUrl(data: Record<string, unknown>): string {
  const keys = [
    "imagem_url",
    "imagemUrl",
    "fotoUrl",
    "fotoURL",
    "FOTO_URL",
    "imageUrl",
    "imageURL",
    "photoUrl",
    "photoURL",
    "urlFoto",
    "foto",
    "FOTO",
    "avatarUrl",
    "profilePhotoUrl",
    "logoProcessedUrl",
    "logoUrl",
    "photoMedium",
    "photoThumb",
  ];
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim().startsWith("http")) {
      return v.trim();
    }
  }
  return "";
}

function pickDisplayName(data: Record<string, unknown>): string {
  const n = pickString(data, [
    "NOME_COMPLETO",
    "nome",
    "name",
    "displayName",
    "NOME",
  ]);
  if (n) return n.length > 120 ? n.substring(0, 120) : n;
  return "Membro";
}

/**
 * Denormaliza foto/nome do membro para leitura rápida no Chat Igreja
 * (`igrejas/{tenantId}/chat_peer_profiles/{authUid}`).
 */
export const onIgrejaMembroWriteChatPeerProfile = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/membros/{membroId}")
  .onWrite(async (change, context) => {
    const tenantId = String(context.params.tenantId || "").trim();
    const membroId = String(context.params.membroId || "").trim();
    if (!tenantId || !membroId) return null;

    const after = change.after.exists ? (change.after.data() as Record<string, unknown>) : null;
    const authUid = after
      ? pickString(after, ["authUid", "firebaseUid", "uid", "userId"])
      : pickString(
          (change.before.data() || {}) as Record<string, unknown>,
          ["authUid", "firebaseUid", "uid", "userId"],
        );

    if (!authUid) return null;

    const profileRef = admin
      .firestore()
      .collection("igrejas")
      .doc(tenantId)
      .collection("chat_peer_profiles")
      .doc(authUid);

    if (!after) {
      try {
        await profileRef.delete();
      } catch (e) {
        functions.logger.warn("chatPeerProfile: delete", { tenantId, authUid, e });
      }
      return null;
    }

    const st = pickString(after, ["STATUS", "status"]).toLowerCase();
    if (st && st !== "ativo") {
      try {
        await profileRef.delete();
      } catch (_) {}
      return null;
    }

    const photoUrl = pickPhotoUrl(after);
    const displayName = pickDisplayName(after);
    const revRaw = after.fotoUrlCacheRevision ?? after.photoCacheRevision;
    const fotoUrlCacheRevision =
      typeof revRaw === "number" && Number.isFinite(revRaw)
        ? Math.floor(revRaw)
        : typeof revRaw === "string" && revRaw.trim()
          ? parseInt(revRaw, 10) || 0
          : 0;

    await profileRef.set(
      {
        authUid,
        memberDocId: membroId,
        displayName,
        photoUrl: photoUrl || null,
        fotoUrlCacheRevision,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return null;
  });
