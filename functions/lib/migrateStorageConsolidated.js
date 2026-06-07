"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.migrateStorageConsolidated = void 0;
exports.runStorageConsolidationMigration = runStorageConsolidationMigration;
/**
 * Migração Storage → arquitetura consolidada (membros, avisos, eventos, património).
 * Callable master + uso via `node lib/migrateStorageConsolidatedCli.js` após build.
 */
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const sharp_1 = __importDefault(require("sharp"));
const membersDirectoryCache_1 = require("./membersDirectoryCache");
async function isMasterPanelActor(uid, tokenRole, email) {
    const role = String(tokenRole ?? "").trim().toLowerCase();
    if (role === "master" || role === "adm" || role === "admin")
        return true;
    if (email === "raihom@gmail.com")
        return true;
    try {
        const adminDoc = await db.collection("admins").doc(uid).get();
        if (adminDoc.exists)
            return true;
    }
    catch (_) { }
    return false;
}
const db = admin.firestore();
const bucket = admin.storage().bucket();
const PROFILE_FULL = 1024;
const PROFILE_THUMB = 200;
const PROFILE_FULL_Q = 80;
const PROFILE_THUMB_Q = 70;
async function downloadBuffer(path) {
    try {
        const file = bucket.file(path);
        const [exists] = await file.exists();
        if (!exists)
            return null;
        const [buf] = await file.download();
        return buf && buf.length > 32 ? buf : null;
    }
    catch {
        return null;
    }
}
async function saveWebp(path, buffer) {
    const token = db.collection("_meta").doc().id;
    await bucket.file(path).save(buffer, {
        metadata: {
            contentType: "image/webp",
            cacheControl: "public,max-age=31536000",
            metadata: { firebaseStorageDownloadTokens: token },
        },
        resumable: false,
    });
    const encoded = encodeURIComponent(path);
    return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
}
async function encodeMemberTiers(buf) {
    const [full, thumb] = await Promise.all([
        (0, sharp_1.default)(buf)
            .rotate()
            .resize(PROFILE_FULL, PROFILE_FULL, { fit: "cover" })
            .webp({ quality: PROFILE_FULL_Q })
            .toBuffer(),
        (0, sharp_1.default)(buf)
            .rotate()
            .resize(PROFILE_THUMB, PROFILE_THUMB, { fit: "cover" })
            .webp({ quality: PROFILE_THUMB_Q })
            .toBuffer(),
    ]);
    return { full, thumb };
}
function pickHttpUrl(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http"))
            return v.trim();
    }
    return "";
}
async function bufferFromHttp(url) {
    try {
        const res = await fetch(url);
        if (!res.ok)
            return null;
        const ab = await res.arrayBuffer();
        const buf = Buffer.from(ab);
        return buf.length > 32 ? buf : null;
    }
    catch {
        return null;
    }
}
async function memberSourceCandidates(tenantId, memberId, data) {
    const tid = tenantId.trim();
    const mid = memberId.trim();
    const cpf = String(data.CPF ?? data.cpf ?? "").replace(/\D/g, "");
    const auth = String(data.authUid ?? data.firebaseUid ?? "").trim();
    const stems = new Set([mid]);
    if (cpf.length === 11)
        stems.add(cpf);
    if (auth && auth !== mid)
        stems.add(auth);
    const paths = [];
    for (const s of stems) {
        paths.push(`igrejas/${tid}/membros/fotos/${s}.webp`, `igrejas/${tid}/membros/${s}/foto_perfil.webp`, `igrejas/${tid}/membros/${s}/foto_perfil.jpg`, `igrejas/${tid}/membros/${s}/foto_perfil.jpeg`, `igrejas/${tid}/membros/${s}/foto_perfil.png`, `igrejas/${tid}/membros/${s}.jpg`);
    }
    const http = pickHttpUrl(data, [
        "fotoUrl",
        "FOTO_URL_OU_ID",
        "foto_url",
        "photoURL",
        "photoUrl",
    ]);
    if (http && !http.includes("dicebear.com")) {
        paths.push(`__http__:${http}`);
    }
    return paths;
}
async function resolveMemberSourceBuffer(tenantId, memberId, data) {
    const fullPath = `igrejas/${tenantId.trim()}/membros/fotos/${memberId.trim()}.webp`;
    const existingFull = await downloadBuffer(fullPath);
    if (existingFull)
        return existingFull;
    for (const p of await memberSourceCandidates(tenantId, memberId, data)) {
        if (p.startsWith("__http__:")) {
            const buf = await bufferFromHttp(p.slice(9));
            if (buf)
                return buf;
            continue;
        }
        const buf = await downloadBuffer(p);
        if (buf)
            return buf;
    }
    return null;
}
async function migrateMemberDoc(tenantId, memberId, data, dryRun) {
    const tid = tenantId.trim();
    const mid = memberId.trim();
    if (!tid || !mid)
        return false;
    const thumbPath = `igrejas/${tid}/membros/thumbs/${mid}.webp`;
    const fullPath = `igrejas/${tid}/membros/fotos/${mid}.webp`;
    const hasThumb = (await bucket.file(thumbPath).exists())[0];
    const hasFull = (await bucket.file(fullPath).exists())[0];
    const hasThumbUrl = typeof data.fotoThumbUrl === "string" && data.fotoThumbUrl.startsWith("http");
    if (hasFull && hasThumb && hasThumbUrl)
        return false;
    const src = await resolveMemberSourceBuffer(tid, mid, data);
    if (!src)
        return false;
    if (dryRun)
        return true;
    const tiers = await encodeMemberTiers(src);
    let fotoUrl = pickHttpUrl(data, ["fotoUrl", "FOTO_URL_OU_ID", "foto_url", "photoURL"]);
    let fotoThumbUrl = pickHttpUrl(data, ["fotoThumbUrl", "photoThumb"]);
    if (!hasFull || !fotoUrl) {
        fotoUrl = await saveWebp(fullPath, tiers.full);
    }
    if (!hasThumb || !fotoThumbUrl) {
        fotoThumbUrl = await saveWebp(thumbPath, tiers.thumb);
    }
    await db
        .collection("igrejas")
        .doc(tid)
        .collection("membros")
        .doc(mid)
        .set({
        fotoUrl,
        fotoThumbUrl,
        FOTO_URL_OU_ID: fotoUrl,
        foto_url: fotoUrl,
        photoURL: fotoUrl,
        photoThumb: fotoThumbUrl,
        photoStoragePath: fullPath,
        photoThumbStoragePath: thumbPath,
        photoMedium: admin.firestore.FieldValue.delete(),
        photoVariants: admin.firestore.FieldValue.delete(),
        fotoUrlCacheRevision: Date.now(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
}
async function migratePatrimonioDoc(tenantId, itemId, dryRun) {
    const tid = tenantId.trim();
    const iid = itemId.trim();
    let migrated = 0;
    for (let slot = 0; slot < 5; slot++) {
        const n = String(slot + 1).padStart(2, "0");
        const canonImg = `igrejas/${tid}/patrimonio/imagens/${iid}_${n}.webp`;
        const canonThumb = `igrejas/${tid}/patrimonio/thumbs/${iid}_${n}.webp`;
        if ((await bucket.file(canonImg).exists())[0])
            continue;
        const legacy = [
            `igrejas/${tid}/patrimonio/${iid}/galeria_${n}.webp`,
            `igrejas/${tid}/patrimonio/${iid}/galeria_${n}.jpg`,
        ];
        let src = null;
        for (const p of legacy) {
            src = await downloadBuffer(p);
            if (src)
                break;
        }
        if (!src)
            continue;
        if (dryRun) {
            migrated += 1;
            continue;
        }
        const [fullBuf, thumbBuf] = await Promise.all([
            (0, sharp_1.default)(src).rotate().resize(1920, 1920, { fit: "inside", withoutEnlargement: true }).webp({ quality: 78 }).toBuffer(),
            (0, sharp_1.default)(src).rotate().resize(200, 200, { fit: "cover" }).webp({ quality: 70 }).toBuffer(),
        ]);
        await saveWebp(canonImg, fullBuf);
        await saveWebp(canonThumb, thumbBuf);
        migrated += 1;
    }
    return migrated;
}
async function migrateLegacyFeedFolder(tenantId, module, dryRun) {
    const tid = tenantId.trim();
    const prefix = `igrejas/${tid}/${module}/`;
    let migrated = 0;
    const [files] = await bucket.getFiles({ prefix, maxResults: 500 });
    for (const file of files) {
        const name = file.name;
        if (name.includes("/imagens/") || name.includes("/thumbs/") || name.includes("/videos/")) {
            continue;
        }
        const aviso = name.match(new RegExp(`^igrejas/${tid}/avisos/([^/]+)/(capa_aviso|galeria_\\d+)\\.(jpe?g|png|webp)$`, "i"));
        const evento = name.match(new RegExp(`^igrejas/${tid}/eventos/([^/]+)/(banner_evento|galeria_\\d+)\\.(jpe?g|png|webp)$`, "i"));
        const m = module === "avisos" ? aviso : evento;
        if (!m)
            continue;
        const postId = m[1];
        const base = m[2];
        const suffix = base === "capa_aviso" || base === "banner_evento"
            ? base.replace("capa_aviso", "capa").replace("banner_evento", "banner")
            : base;
        const dest = `igrejas/${tid}/${module}/imagens/${postId}_${suffix}.webp`;
        if ((await bucket.file(dest).exists())[0])
            continue;
        const buf = await downloadBuffer(name);
        if (!buf)
            continue;
        if (dryRun) {
            migrated += 1;
            continue;
        }
        const out = await (0, sharp_1.default)(buf)
            .rotate()
            .resize(1920, 1920, { fit: "inside", withoutEnlargement: true })
            .webp({ quality: 78 })
            .toBuffer();
        await saveWebp(dest, out);
        migrated += 1;
    }
    return migrated;
}
async function migrateEventVideoThumbs(tenantId, dryRun) {
    const tid = tenantId.trim();
    const prefix = `igrejas/${tid}/eventos/videos/`;
    let migrated = 0;
    const [files] = await bucket.getFiles({ prefix, maxResults: 200 });
    for (const file of files) {
        const m = file.name.match(/_v(\d)_thumb\.(jpg|jpeg|webp)$/i);
        if (!m)
            continue;
        const postM = file.name.match(/\/([^/]+)_v\d_thumb\./);
        if (!postM)
            continue;
        const postId = postM[1];
        const slot = m[1];
        const dest = `igrejas/${tid}/eventos/thumbs/${postId}_v${slot}.webp`;
        if ((await bucket.file(dest).exists())[0])
            continue;
        const buf = await downloadBuffer(file.name);
        if (!buf)
            continue;
        if (dryRun) {
            migrated += 1;
            continue;
        }
        const out = await (0, sharp_1.default)(buf).rotate().resize(200, 200, { fit: "cover" }).webp({ quality: 70 }).toBuffer();
        await saveWebp(dest, out);
        migrated += 1;
    }
    return migrated;
}
async function listTenantIds(allTenants, tenantId) {
    if (tenantId?.trim())
        return [tenantId.trim()];
    if (!allTenants)
        return [];
    const snap = await db.collection("igrejas").limit(500).get();
    return snap.docs.map((d) => d.id);
}
async function runStorageConsolidationMigration(options) {
    const dryRun = options.dryRun !== false;
    const modules = options.modules?.length ? options.modules : ["all"];
    const runAll = modules.includes("all");
    const limit = options.limitPerTenant ?? 2000;
    const errors = [];
    const result = {
        ok: true,
        dryRun,
        tenantsProcessed: 0,
        membros: 0,
        avisos: 0,
        eventos: 0,
        patrimonio: 0,
        directoriesRefreshed: 0,
        errors,
    };
    const tenantIds = await listTenantIds(!!options.allTenants, options.tenantId);
    if (!tenantIds.length) {
        errors.push("Nenhum tenantId — use tenantId ou allTenants:true");
        result.ok = false;
        return result;
    }
    for (const tid of tenantIds) {
        try {
            if (runAll || modules.includes("membros")) {
                const memSnap = await db.collection("igrejas").doc(tid).collection("membros").limit(limit).get();
                for (const doc of memSnap.docs) {
                    try {
                        const ok = await migrateMemberDoc(tid, doc.id, doc.data(), dryRun);
                        if (ok)
                            result.membros += 1;
                    }
                    catch (e) {
                        errors.push(`membros/${tid}/${doc.id}: ${e}`);
                    }
                }
                if (!dryRun) {
                    const refreshSnap = await db.collection("igrejas").doc(tid).collection("membros").limit(800).get();
                    await (0, membersDirectoryCache_1.recomputeMembersDirectoryFromDocs)(tid, refreshSnap.docs, refreshSnap.size);
                    result.directoriesRefreshed += 1;
                }
            }
            if (runAll || modules.includes("patrimonio")) {
                const patSnap = await db.collection("igrejas").doc(tid).collection("patrimonio").limit(limit).get();
                for (const doc of patSnap.docs) {
                    try {
                        result.patrimonio += await migratePatrimonioDoc(tid, doc.id, dryRun);
                    }
                    catch (e) {
                        errors.push(`patrimonio/${tid}/${doc.id}: ${e}`);
                    }
                }
            }
            if (runAll || modules.includes("avisos")) {
                try {
                    result.avisos += await migrateLegacyFeedFolder(tid, "avisos", dryRun);
                }
                catch (e) {
                    errors.push(`avisos/${tid}: ${e}`);
                }
            }
            if (runAll || modules.includes("eventos")) {
                try {
                    result.eventos += await migrateLegacyFeedFolder(tid, "eventos", dryRun);
                    result.eventos += await migrateEventVideoThumbs(tid, dryRun);
                }
                catch (e) {
                    errors.push(`eventos/${tid}: ${e}`);
                }
            }
            result.tenantsProcessed += 1;
        }
        catch (e) {
            errors.push(`tenant/${tid}: ${e}`);
        }
    }
    result.ok = errors.length === 0;
    return result;
}
/** Painel Master — migra Storage + Firestore para arquitetura consolidada. */
exports.migrateStorageConsolidated = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "2GB" })
    .https.onCall(async (request, context) => {
    const email = String(context.auth?.token?.email || "").trim().toLowerCase();
    if (!context.auth || !(await isMasterPanelActor(context.auth.uid, context.auth.token?.role, email))) {
        throw new functions.https.HttpsError("permission-denied", "Apenas operador do painel master.");
    }
    const body = (request || {});
    const tenantId = String(body.tenantId || body.igrejaId || "").trim();
    const allTenants = body.allTenants === true;
    const execute = body.execute === true;
    const modulesRaw = body.modules;
    const modules = Array.isArray(modulesRaw)
        ? modulesRaw.map(String)
        : ["all"];
    const out = await runStorageConsolidationMigration({
        tenantId: tenantId || undefined,
        allTenants: allTenants || !tenantId,
        modules,
        dryRun: !execute,
        limitPerTenant: typeof body.limit === "number" ? body.limit : 2000,
    });
    return {
        ...out,
        message: execute
            ? "Migração Storage consolidada executada."
            : "Simulação (dry-run). Envie execute:true para aplicar.",
    };
});
//# sourceMappingURL=migrateStorageConsolidated.js.map