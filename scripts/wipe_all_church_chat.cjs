'use strict';
/**
 * Apaga TODO o chat (mensagens + fotos + vídeos) de TODAS as igrejas.
 *  - Dry-run por padrão: só CONTA threads/mensagens/mídias, não apaga nada.
 *  - Com --apply: apaga mensagens (Firestore) + arquivos de mídia (Storage) +
 *    docs de thread + chat_uploads pendentes.
 * IRREVERSÍVEL. Escopo: todas as igrejas em `igrejas/{tenantId}`.
 *
 * Uso:
 *   node scripts/wipe_all_church_chat.cjs            # dry-run (conta)
 *   node scripts/wipe_all_church_chat.cjs --apply     # APAGA de verdade
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');
const BUCKET = 'gestaoyahweh-21e23.firebasestorage.app';
const APPLY = process.argv.includes('--apply');

admin.initializeApp({
  credential: admin.credential.cert(require(KEY)),
  storageBucket: BUCKET,
});
const db = admin.firestore();
const bucket = admin.storage().bucket();

const stats = { tenants: 0, threads: 0, messages: 0, media: 0, mediaDeleted: 0, uploads: 0 };

async function deleteStoragePath(p) {
  const sp = String(p || '').trim();
  if (!sp) return false;
  if (!APPLY) return true; // conta como "seria apagado"
  try {
    await bucket.file(sp).delete({ ignoreNotFound: true });
    return true;
  } catch (e) {
    console.warn(`  [storage] falha ${sp}: ${e.message}`);
    return false;
  }
}

async function wipeThreadMessages(threadRef) {
  const msgsCol = threadRef.collection('messages');
  while (true) {
    const snap = await msgsCol.limit(300).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      stats.messages++;
      for (const key of ['storagePath', 'thumbStoragePath', 'thumbnailStoragePath']) {
        if (d[key]) {
          stats.media++;
          if (await deleteStoragePath(d[key])) stats.mediaDeleted++;
        }
      }
      if (APPLY) batch.delete(doc.ref);
    }
    if (APPLY) await batch.commit();
    if (snap.size < 300) break;
    if (!APPLY) break; // dry-run: 1 página basta para amostra? Não — contamos tudo:
  }
}

// Dry-run precisa contar TODAS as mensagens (não só 1 página). Refaz sem o break.
async function countThreadMessages(threadRef) {
  const msgsCol = threadRef.collection('messages');
  let last = null;
  while (true) {
    let q = msgsCol.orderBy('__name__').limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      stats.messages++;
      for (const key of ['storagePath', 'thumbStoragePath', 'thumbnailStoragePath']) {
        if (d[key]) stats.media++;
      }
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }
}

async function wipeTenantUploads(tenantRef) {
  const upCol = tenantRef.collection('chat_uploads');
  let last = null;
  while (true) {
    let q = upCol.orderBy('__name__').limit(300);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      stats.uploads++;
      for (const key of ['storagePath', 'thumbStoragePath']) {
        if (d[key]) { stats.media++; if (await deleteStoragePath(d[key])) stats.mediaDeleted++; }
      }
      if (APPLY) batch.delete(doc.ref);
    }
    if (APPLY) await batch.commit();
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 300) break;
  }
}

async function main() {
  console.log(`=== WIPE CHAT — modo: ${APPLY ? 'APPLY (APAGA DE VERDADE)' : 'DRY-RUN (só conta)'} ===\n`);
  const igrejas = await db.collection('igrejas').get();
  for (const ig of igrejas.docs) {
    stats.tenants++;
    const tenantRef = ig.ref;
    const chats = await tenantRef.collection('chats').get();
    console.log(`igreja ${ig.id}: ${chats.size} threads`);
    for (const thread of chats.docs) {
      stats.threads++;
      if (APPLY) {
        await wipeThreadMessages(thread.ref);
        await thread.ref.delete();
      } else {
        await countThreadMessages(thread.ref);
      }
    }
    await wipeTenantUploads(tenantRef);
  }
  console.log('\n=== TOTAIS ===');
  console.log(`igrejas: ${stats.tenants}`);
  console.log(`threads de chat: ${stats.threads}`);
  console.log(`mensagens: ${stats.messages}`);
  console.log(`arquivos de mídia (fotos/vídeos): ${stats.media}${APPLY ? ` (apagados: ${stats.mediaDeleted})` : ''}`);
  console.log(`chat_uploads pendentes: ${stats.uploads}`);
  if (!APPLY) {
    console.log('\n(DRY-RUN — nada foi apagado. Rode com --apply para apagar de verdade.)');
  } else {
    console.log('\n✅ Chat apagado de todas as igrejas.');
  }
  process.exit(0);
}
main().catch((e) => { console.error('fatal:', e.message); process.exit(1); });
