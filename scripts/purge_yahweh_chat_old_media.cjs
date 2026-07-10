/**
 * Limpeza cirúrgica YahwehChat — mensagens/mídia antigas.
 *
 * 1) Apaga docs com expiresAt < agora (e Storage se houver storagePath)
 * 2) Mensagens de mídia sem expiresAt com createdAt > 90 dias
 * 3) Opcional: ficheiros órfãos em Storage chat_media/ (prefixo)
 *
 * Uso (raiz do repo):
 *   node scripts/purge_yahweh_chat_old_media.cjs
 *   node scripts/purge_yahweh_chat_old_media.cjs --church=igreja_o_brasil_para_cristo_jardim_goiano
 *   node scripts/purge_yahweh_chat_old_media.cjs --dry-run
 *   node scripts/purge_yahweh_chat_old_media.cjs --days=90 --max=2000
 */
'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const churchArg = args.find((a) => a.startsWith('--church='));
const churchFilter = churchArg ? churchArg.split('=')[1].trim() : '';
const daysArg = args.find((a) => a.startsWith('--days='));
const retentionDays = daysArg ? parseInt(daysArg.split('=')[1], 10) : 90;
const maxArg = args.find((a) => a.startsWith('--max='));
const maxDelete = maxArg ? parseInt(maxArg.split('=')[1], 10) : 2000;

function findSa() {
  const candidates = [
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(root, 'ANDROID'),
    path.join(root, 'functions'),
  ].filter(Boolean);
  for (const c of candidates) {
    if (c && c.endsWith('.json') && fs.existsSync(c)) return c;
  }
  const androidDir = path.join(root, 'ANDROID');
  if (fs.existsSync(androidDir)) {
    const hit = fs
      .readdirSync(androidDir)
      .find((f) => f.includes('firebase-adminsdk') && f.endsWith('.json'));
    if (hit) return path.join(androidDir, hit);
  }
  throw new Error(
    'Conta de serviço não encontrada (ANDROID/*-firebase-adminsdk*.json).',
  );
}

async function deleteStorage(bucket, storagePath) {
  const p = String(storagePath || '').trim();
  if (!p) return;
  try {
    await bucket.file(p).delete({ ignoreNotFound: true });
  } catch (e) {
    console.warn('storage delete fail', p, e.message || e);
  }
}

async function purgeExpiredByField(db, bucket) {
  const now = admin.firestore.Timestamp.now();
  let deleted = 0;
  for (let round = 0; round < 40 && deleted < maxDelete; round++) {
    let snap;
    try {
      snap = await db
        .collectionGroup('messages')
        .where('expiresAt', '<', now)
        .limit(400)
        .get();
    } catch (e) {
      console.warn('expiresAt query falhou (índice?):', e.message || e);
      break;
    }
    if (snap.empty) break;
    for (const doc of snap.docs) {
      if (deleted >= maxDelete) break;
      if (churchFilter) {
        const parts = doc.ref.path.split('/');
        // igrejas/{churchId}/chats/{id}/messages/{msg}
        if (parts[0] !== 'igrejas' || parts[1] !== churchFilter) continue;
      }
      const d = doc.data() || {};
      if (!dryRun) {
        await deleteStorage(bucket, d.storagePath);
        await deleteStorage(bucket, d.thumbStoragePath);
        await doc.ref.delete();
      }
      deleted++;
    }
    if (snap.size < 400) break;
  }
  return deleted;
}

async function purgeOldMediaWithoutExpiry(db, bucket) {
  const cutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000),
  );
  const mediaTypes = new Set(['image', 'video', 'audio', 'file', 'document', 'voice']);
  let deleted = 0;
  const churches = churchFilter
    ? [churchFilter]
    : (
        await db.collection('igrejas').select().limit(80).get()
      ).docs.map((d) => d.id);

  for (const churchId of churches) {
    if (deleted >= maxDelete) break;
    const chats = await db
      .collection('igrejas')
      .doc(churchId)
      .collection('chats')
      .orderBy('lastMessageAt', 'desc')
      .limit(40)
      .get()
      .catch(async () =>
        db.collection('igrejas').doc(churchId).collection('chats').limit(40).get(),
      );

    for (const thread of chats.docs) {
      if (deleted >= maxDelete) break;
      let msgs;
      try {
        msgs = await thread.ref
          .collection('messages')
          .where('createdAt', '<', cutoff)
          .orderBy('createdAt', 'desc')
          .limit(30)
          .get();
      } catch (_) {
        continue;
      }
      for (const msg of msgs.docs) {
        if (deleted >= maxDelete) break;
        const d = msg.data() || {};
        if (d.preserveMedia === true) continue;
        const type = String(d.type || 'text');
        if (!mediaTypes.has(type)) continue;
        const path = String(d.storagePath || '').trim();
        const url = String(d.mediaUrl || '').trim();
        if (!path && !url) continue;
        // Se ainda tem expiresAt no futuro, a CF trata — não forçar.
        if (d.expiresAt && d.expiresAt.toMillis && d.expiresAt.toMillis() > Date.now()) {
          continue;
        }
        if (!dryRun) {
          await deleteStorage(bucket, d.storagePath);
          await deleteStorage(bucket, d.thumbStoragePath);
          await msg.ref.delete();
        }
        deleted++;
      }
    }
  }
  return deleted;
}

async function main() {
  const sa = findSa();
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(require(sa)),
      storageBucket:
        process.env.FIREBASE_STORAGE_BUCKET ||
        'gestaoyahweh-21e23.firebasestorage.app',
    });
  }
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  console.log(
    `YahwehChat purge | dryRun=${dryRun} days=${retentionDays} max=${maxDelete} church=${churchFilter || 'ALL'}`,
  );
  const a = await purgeExpiredByField(db, bucket);
  console.log(`expiresAt vencidos: ${a}${dryRun ? ' (dry-run)' : ''}`);
  const b = await purgeOldMediaWithoutExpiry(db, bucket);
  console.log(`mídia >${retentionDays}d: ${b}${dryRun ? ' (dry-run)' : ''}`);
  console.log('OK');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
