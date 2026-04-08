/**
 * Limpa mídia da igreja (Firestore + Storage) para novo recarregamento.
 *
 * Escopo:
 * - Logo da igreja (doc igrejas/{id})
 * - Fotos de membros (subcoleção membros) — documentos permanecem; só URLs/campos de mídia
 * - Mídias de avisos/eventos (noticias, avisos, eventos, mural)
 * - Fotos de patrimônio (subcoleção patrimonio)
 * - Configs de certificado/carteirinha com logo personalizada
 * - Passo final: apaga **todo** o prefixo `igrejas/{id}/` no Storage (órfãos incluídos)
 *
 * Segurança:
 * - Modo padrão: DRY-RUN (não altera nada)
 * - Para executar de verdade: --execute
 *
 * Uso (na pasta functions):
 *   node scripts/clean-tenant-media.js --dry-run
 *   node scripts/clean-tenant-media.js --execute
 *   node scripts/clean-tenant-media.js --igreja=ID_EXATO --execute
 *
 * Credenciais:
 *   GOOGLE_APPLICATION_CREDENTIALS ou gcloud auth application-default login
 */

const admin = require("firebase-admin");

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "gestaoyahweh-21e23";

const defaultBucket =
  process.env.FIREBASE_STORAGE_BUCKET ||
  process.env.STORAGE_BUCKET ||
  "gestaoyahweh-21e23.firebasestorage.app";

const args = process.argv.slice(2);
const igArg = args.find((a) => a.startsWith("--igreja="));
const igrejaPreferida = igArg
  ? igArg.split("=")[1].trim()
  : "igreja_o_brasil_para_cristo_jardim_goiano";
const execute = args.includes("--execute");
const dryRun = !execute || args.includes("--dry-run");

if (!admin.apps.length) {
  admin.initializeApp({
    projectId,
    storageBucket: defaultBucket,
  });
}

const db = admin.firestore();
const bucket = admin.storage().bucket(defaultBucket);
const FieldValue = admin.firestore.FieldValue;
const FieldPath = admin.firestore.FieldPath;

const CHURCH_MEDIA_KEYS = [
  "logoUrl",
  "logo_url",
  "logoProcessedUrl",
  "logoProcessed",
  "logoPath",
  "logoStoragePath",
  "logoStorage",
  "logoVariants",
  "logoDataBase64",
  "logoBase64",
  "logoCertificado",
  "logoCertificadoUrl",
  "logoCertificadoPath",
];

const MEMBER_MEDIA_KEYS = [
  "FOTO_URL_OU_ID",
  "fotoUrl",
  "photoUrl",
  "photoURL",
  "imageUrl",
  "defaultImageUrl",
  "imageUrls",
  "fotoUrls",
  "photoUrls",
  "imageVariants",
  "fotoVariants",
  "photoVariants",
  "photoStoragePath",
  "imageStoragePath",
  "fotoStoragePaths",
  "fotoPath",
  "imagePath",
  "storagePath",
  "fullPath",
  "avatarUrl",
  "assinaturaUrl",
  "assinatura_url",
  "carteirinhaAssinaturaUrl",
  "carteirinha_assinatura_url",
];

const NEWS_MEDIA_KEYS = [
  "imageUrl",
  "defaultImageUrl",
  "imageUrls",
  "fotoUrls",
  "photos",
  "coverUrl",
  "capaUrl",
  "posterUrl",
  "thumbUrl",
  "thumbnailUrl",
  "previewImageUrl",
  "videoUrl",
  "videos",
  "videoUrls",
  "video_url",
  "videoPath",
  "videoStoragePath",
  "thumbStoragePath",
  "imageStoragePath",
  "imageStoragePaths",
  "imageVariants",
  "videoVariants",
  "fotoVariants",
];

const PATRIMONIO_MEDIA_KEYS = [
  "imageUrl",
  "defaultImageUrl",
  "fotoUrls",
  "imageUrls",
  "imageVariants",
  "fotoVariants",
  "fotoStoragePaths",
  "imageStoragePath",
  "fotoPath",
  "storagePath",
  "path",
  "photoUrl",
];

const CONFIG_MEDIA_KEYS = [
  "logoUrl",
  "logo_url",
  "logoPath",
  "logoVariants",
  "logoDataBase64",
  "logoBase64",
  "logoCertificado",
  "logoCertificadoUrl",
  "logoCertificadoPath",
];

const NEWS_SUBCOLLECTIONS = [
  "noticias",
  "avisos",
  "eventos",
  "mural",
  "mural_avisos",
  "mural_eventos",
];

const CONFIG_SUBCOLLECTIONS = [
  "config",
  "configs",
];

function safeStr(v) {
  return (v ?? "").toString().trim();
}

function maybeFirebaseDownloadPath(url) {
  try {
    const u = new URL(url);
    if (!u.hostname.includes("firebasestorage")) return null;
    const marker = "/o/";
    const idx = u.pathname.indexOf(marker);
    if (idx < 0) return null;
    const encoded = u.pathname.slice(idx + marker.length);
    if (!encoded) return null;
    return decodeURIComponent(encoded).replace(/^\/+/, "");
  } catch (_) {
    return null;
  }
}

function maybeGsPath(gsUrl) {
  const raw = safeStr(gsUrl);
  if (!raw.toLowerCase().startsWith("gs://")) return null;
  const noScheme = raw.slice(5);
  const slash = noScheme.indexOf("/");
  if (slash < 0) return null;
  return noScheme.slice(slash + 1).replace(/^\/+/, "");
}

function maybeRawStoragePath(raw) {
  const s = safeStr(raw);
  if (!s) return null;
  if (s.startsWith("http://") || s.startsWith("https://")) return null;
  if (s.startsWith("data:")) return null;
  if (s.toLowerCase().startsWith("gs://")) return maybeGsPath(s);
  if (s.includes("/")) return s.replace(/^\/+/, "");
  return null;
}

function collectFromAny(raw, out) {
  if (raw == null) return;
  if (typeof raw === "string") {
    const s = safeStr(raw);
    if (!s) return;
    out.urls.add(s);
    const p1 = maybeFirebaseDownloadPath(s);
    if (p1) out.paths.add(p1);
    const p2 = maybeGsPath(s);
    if (p2) out.paths.add(p2);
    const p3 = maybeRawStoragePath(s);
    if (p3) out.paths.add(p3);
    return;
  }
  if (Array.isArray(raw)) {
    for (const item of raw) collectFromAny(item, out);
    return;
  }
  if (typeof raw === "object") {
    for (const [k, v] of Object.entries(raw)) {
      const low = k.toLowerCase();
      if (
        low.includes("url") ||
        low.includes("path") ||
        low.includes("storage") ||
        low.includes("thumb") ||
        low.includes("image") ||
        low.includes("video") ||
        low.includes("logo")
      ) {
        collectFromAny(v, out);
      } else if (Array.isArray(v) || (v && typeof v === "object")) {
        collectFromAny(v, out);
      }
    }
  }
}

function collectDocMedia(docData, keys) {
  const out = { urls: new Set(), paths: new Set() };
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(docData, key)) {
      collectFromAny(docData[key], out);
    }
  }
  return out;
}

function buildDeleteUpdate(docData, keys) {
  const update = {};
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(docData, key)) {
      update[key] = FieldValue.delete();
    }
  }
  return update;
}

async function resolveIgrejaId(preferred) {
  const tryIds = [
    preferred,
    "igreja_o_brasil_para_cristo_jardim_goiano",
    "brasilparacristo_sistema",
    "brasilparacristo",
    "iobpc-jardim-goiano",
  ];
  const seen = new Set();
  for (const id of tryIds) {
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const d = await db.collection("igrejas").doc(id).get();
    if (d.exists) return { id, snap: d };
  }
  const all = await db.collection("igrejas").get();
  const re = /brasil.*cristo|o\s+brasil\s+para\s+cristo/i;
  for (const d of all.docs) {
    const data = d.data() || {};
    const nome = `${data.nome || data.name || ""} ${data.slug || data.alias || ""}`;
    if (re.test(nome)) return { id: d.id, snap: d };
  }
  return null;
}

async function deleteStoragePaths(pathsSet) {
  let ok = 0;
  let fail = 0;
  for (const p of pathsSet) {
    const path = safeStr(p);
    if (!path) continue;
    if (dryRun) {
      console.log(`  [dry-run] delete storage: ${path}`);
      ok++;
      continue;
    }
    try {
      await bucket.file(path).delete({ ignoreNotFound: true });
      ok++;
    } catch (e) {
      fail++;
      console.log(`  [warn] falha ao deletar ${path}: ${e?.message || e}`);
    }
  }
  return { ok, fail };
}

/**
 * Remove todos os arquivos sob igrejas/{tenantId}/ (inclui órfãos não referenciados no Firestore).
 */
async function deleteAllUnderTenantStoragePrefix(tenantId) {
  const prefix = `igrejas/${safeStr(tenantId).replace(/^\/+|\/+$/g, "")}/`;
  if (prefix === "igrejas//") return { ok: 0, fail: 0 };
  let ok = 0;
  let fail = 0;
  console.log(`\n7) Storage — exclusão recursiva do prefixo: ${prefix}`);
  if (dryRun) {
    const [files] = await bucket.getFiles({ prefix, maxResults: 500 });
    for (const f of files) {
      console.log(`  [dry-run] delete storage: ${f.name}`);
      ok++;
    }
    return { ok, fail };
  }
  const [files] = await bucket.getFiles({ prefix, autoPaginate: true });
  for (const f of files) {
    try {
      await f.delete({ ignoreNotFound: true });
      ok++;
    } catch (e) {
      fail++;
      console.log(`  [warn] falha ao deletar ${f.name}: ${e?.message || e}`);
    }
  }
  return { ok, fail };
}

async function cleanCollectionByKeys(colRef, keys, label, stats, mediaAccumulator) {
  let last = null;
  for (;;) {
    let q = colRef.orderBy(FieldPath.documentId()).limit(300);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    let batch = db.batch();
    let ops = 0;
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const media = collectDocMedia(data, keys);
      for (const u of media.urls) mediaAccumulator.urls.add(u);
      for (const p of media.paths) mediaAccumulator.paths.add(p);

      const update = buildDeleteUpdate(data, keys);
      if (Object.keys(update).length > 0) {
        if (!dryRun) {
          batch.update(doc.ref, update);
        }
        ops++;
        stats.firestoreFieldsDeleted += Object.keys(update).length;
      }
      stats.docsScanned++;
      stats[`docs${label}`] = (stats[`docs${label}`] || 0) + 1;
      if (!dryRun && ops >= 450) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
    if (!dryRun && ops > 0) {
      await batch.commit();
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 300) break;
  }
}

async function cleanConfigSubcollections(igrejaId, stats, mediaAccumulator) {
  for (const sub of CONFIG_SUBCOLLECTIONS) {
    const col = db.collection("igrejas").doc(igrejaId).collection(sub);
    let exists = false;
    try {
      const probe = await col.limit(1).get();
      exists = !probe.empty;
    } catch (_) {
      exists = false;
    }
    if (!exists) continue;
    console.log(`\n- Limpando ${sub}...`);
    await cleanCollectionByKeys(col, CONFIG_MEDIA_KEYS, "Config", stats, mediaAccumulator);
  }
}

async function cleanNewsLikeSubcollections(igrejaId, stats, mediaAccumulator) {
  for (const sub of NEWS_SUBCOLLECTIONS) {
    const col = db.collection("igrejas").doc(igrejaId).collection(sub);
    let exists = false;
    try {
      const probe = await col.limit(1).get();
      exists = !probe.empty;
    } catch (_) {
      exists = false;
    }
    if (!exists) continue;
    console.log(`\n- Limpando ${sub}...`);
    await cleanCollectionByKeys(col, NEWS_MEDIA_KEYS, "News", stats, mediaAccumulator);
  }
}

async function main() {
  console.log(`Projeto: ${projectId}`);
  console.log(`Bucket: ${defaultBucket}`);
  console.log(`Igreja preferida: ${igrejaPreferida}`);
  if (dryRun) {
    console.log("\nMODO DRY-RUN ativo (nenhuma alteração será feita).");
    console.log("Para executar de verdade, rode com: --execute\n");
  }

  const resolved = await resolveIgrejaId(igrejaPreferida);
  if (!resolved) {
    console.error("Igreja não encontrada. Passe --igreja=ID_EXATO do documento em /igrejas.");
    process.exit(1);
  }
  const igrejaId = resolved.id;
  const igrejaSnap = resolved.snap;
  const igrejaData = igrejaSnap.data() || {};
  const nomeIgreja = safeStr(igrejaData.nome || igrejaData.name);

  console.log(`Igreja resolvida: ${igrejaId}`);
  console.log(`Nome: ${nomeIgreja || "(sem nome)"}`);

  const stats = {
    docsScanned: 0,
    firestoreFieldsDeleted: 0,
    storageDeleteOk: 0,
    storageDeleteFail: 0,
  };
  const mediaAccumulator = { urls: new Set(), paths: new Set() };

  // 1) Igreja (logo principal)
  console.log("\n1) Limpando logo da igreja...");
  const churchMedia = collectDocMedia(igrejaData, CHURCH_MEDIA_KEYS);
  for (const u of churchMedia.urls) mediaAccumulator.urls.add(u);
  for (const p of churchMedia.paths) mediaAccumulator.paths.add(p);
  const churchUpdate = buildDeleteUpdate(igrejaData, CHURCH_MEDIA_KEYS);
  if (Object.keys(churchUpdate).length > 0) {
    if (!dryRun) {
      await igrejaSnap.ref.update(churchUpdate);
    }
    stats.firestoreFieldsDeleted += Object.keys(churchUpdate).length;
  }

  // 2) Membros
  console.log("\n2) Limpando mídia de membros...");
  const membrosCol = db.collection("igrejas").doc(igrejaId).collection("membros");
  await cleanCollectionByKeys(membrosCol, MEMBER_MEDIA_KEYS, "Members", stats, mediaAccumulator);

  // 3) Notícias / Avisos / Eventos / Mural
  console.log("\n3) Limpando mídia de avisos/eventos/mural...");
  await cleanNewsLikeSubcollections(igrejaId, stats, mediaAccumulator);

  // 4) Patrimônio
  console.log("\n4) Limpando mídia de patrimônio...");
  const patrimonioCol = db.collection("igrejas").doc(igrejaId).collection("patrimonio");
  await cleanCollectionByKeys(patrimonioCol, PATRIMONIO_MEDIA_KEYS, "Patrimonio", stats, mediaAccumulator);

  // 5) Configs com logo (certificados/carteirinha)
  console.log("\n5) Limpando logos de configs...");
  await cleanConfigSubcollections(igrejaId, stats, mediaAccumulator);

  // 6) Deletar arquivos no Storage (paths extraídos dos docs)
  console.log("\n6) Limpando arquivos do Storage referenciados...");
  const del = await deleteStoragePaths(mediaAccumulator.paths);
  stats.storageDeleteOk += del.ok;
  stats.storageDeleteFail += del.fail;

  // 7) Apagar tudo em igrejas/{id}/ (fotos/vídeos órfãos, thumbs, etc.)
  const del2 = await deleteAllUnderTenantStoragePrefix(igrejaId);
  stats.storageDeleteOk += del2.ok;
  stats.storageDeleteFail += del2.fail;

  console.log("\n===== RESUMO =====");
  console.log(`Igreja: ${igrejaId} (${nomeIgreja || "sem nome"})`);
  console.log(`Docs varridos: ${stats.docsScanned}`);
  console.log(`Campos removidos no Firestore: ${stats.firestoreFieldsDeleted}`);
  console.log(`Paths únicos coletados para deletar no Storage: ${mediaAccumulator.paths.size}`);
  console.log(`Storage deletado OK: ${stats.storageDeleteOk}`);
  console.log(`Storage falhas: ${stats.storageDeleteFail}`);
  console.log(`Modo: ${dryRun ? "DRY-RUN" : "EXECUTE"}`);
  console.log("==================\n");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

