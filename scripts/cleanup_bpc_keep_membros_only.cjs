/**
 * Limpeza BPC — mantém `membros` + Mercado Pago da igreja + doc raiz.
 * Apaga restantes subcoleções Firestore e pastas Storage (exceto membros/).
 *
 * PRESERVA (igreja):
 *   - membros/
 *   - config/mercado_pago
 *   - private/mercado_pago (token sensível, se existir)
 *
 * NÃO TOCA (global Master):
 *   - config/mercado_pago (coleção raiz — credenciais ADM)
 *
 * Igreja canónica: igreja_o_brasil_para_cristo_jardim_goiano
 *
 * Uso (raiz do repo):
 *   node scripts/cleanup_bpc_keep_membros_only.cjs
 *   node scripts/cleanup_bpc_keep_membros_only.cjs --execute
 *   node scripts/cleanup_bpc_keep_membros_only.cjs --church=igreja_o_brasil_para_cristo_jardim_goiano --execute
 *   node scripts/cleanup_bpc_keep_membros_only.cjs --also-legacy --execute
 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
// Preferir firebase-admin instalado em functions/
const admin = (() => {
  try {
    return require(path.join(root, 'functions', 'node_modules', 'firebase-admin'));
  } catch (_) {
    return require('firebase-admin');
  }
})();

const args = process.argv.slice(2);
const dryRun = !args.includes('--execute');
const alsoLegacy = args.includes('--also-legacy');
const churchArg = args.find((a) => a.startsWith('--church='));

const CANONICAL = 'igreja_o_brasil_para_cristo_jardim_goiano';
const LEGACY_IDS = ['brasilparacristo_sistema', 'brasilparacristo'];

/** Coleções inteiras a preservar. */
const KEEP_COLLECTIONS = new Set(['membros']);

/** Dentro de config/private: só estes docs ficam. */
const KEEP_DOCS_BY_COLLECTION = {
  config: new Set(['mercado_pago']),
  private: new Set(['mercado_pago']),
};

/** Subcoleções conhecidas a limpar (além de qualquer outra listada no doc). */
const KNOWN_WIPE = [
  'departamentos',
  'cargos',
  'eventos',
  'avisos',
  'noticias',
  'events',
  'chats',
  'chat_threads',
  'chat_audit',
  'users_profile_chat',
  'pastoral_mensagens',
  'internal_notif_state',
  'notificacoes',
  'patrimonio',
  'patrimonio_inventario_historico',
  'finance',
  'financeiro',
  'finance_logs',
  'finance_mp_notifications',
  'contas',
  'fornecedores',
  'fornecedor_compromissos',
  'escalas',
  'escala_templates',
  'escala_trocas',
  'agenda',
  'lideres',
  'administrativo',
  'doacoes',
  'mercadopago',
  'mp_payment_bridge',
  'mp_preference_bridge',
  'cartoes',
  'certificados_emitidos',
  'certificados_historico',
  'certificados_protocol_index',
  'pedidosOracao',
  'cartas_historico',
  'cartas_modelos',
  'dashboard',
  'dashboard_stats',
  '_dashboard_cache',
  '_panel_cache',
  '_performance_cache',
  'visitantes',
  'pending_uploads',
  'auditoria_tenant',
  'chat_audit',
];

function findSa() {
  const env = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (env && fs.existsSync(env)) return env;
  for (const dir of [
    path.join(root, 'ANDROID'),
    path.join(root, 'secrets'),
    root,
  ]) {
    if (!fs.existsSync(dir)) continue;
    const hit = fs
      .readdirSync(dir)
      .find((f) => /firebase-adminsdk.*\.json$/i.test(f));
    if (hit) return path.join(dir, hit);
  }
  return null;
}

async function deleteCollectionRecursive(db, colRef) {
  let total = 0;
  while (true) {
    const snap = await colRef.limit(80).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const subcols = await doc.ref.listCollections();
      for (const sub of subcols) {
        total += await deleteCollectionRecursive(db, sub);
      }
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    if (dryRun) break;
  }
  return total;
}

async function wipeChurchSubcollections(db, churchId) {
  const churchRef = db.collection('igrejas').doc(churchId);
  const exists = (await churchRef.get()).exists;
  if (!exists) {
    console.log(`  [skip] igrejas/${churchId} não existe`);
    return { docs: 0, cols: [] };
  }

  const listed = await churchRef.listCollections();
  const names = new Set(listed.map((c) => c.id));
  for (const k of KNOWN_WIPE) names.add(k);

  let docs = 0;
  const wiped = [];
  for (const name of [...names].sort()) {
    if (KEEP_COLLECTIONS.has(name)) {
      console.log(`  [keep] ${name}`);
      continue;
    }
    const keepDocs = KEEP_DOCS_BY_COLLECTION[name];
    if (keepDocs) {
      const col = churchRef.collection(name);
      const snap = await col.get();
      let kept = 0;
      let removed = 0;
      for (const d of snap.docs) {
        if (keepDocs.has(d.id)) {
          console.log(`  [keep] ${name}/${d.id}`);
          kept += 1;
          continue;
        }
        const subcols = await d.ref.listCollections();
        for (const sub of subcols) {
          docs += await deleteCollectionRecursive(db, sub);
        }
        if (!dryRun) await d.ref.delete();
        removed += 1;
        docs += 1;
      }
      console.log(
        `  [${dryRun ? 'dry' : 'del'}] ${name}: removed~${removed} kept=${kept}`,
      );
      if (removed > 0) wiped.push(name);
      continue;
    }
    const col = churchRef.collection(name);
    const n = await deleteCollectionRecursive(db, col);
    if (n > 0 || listed.some((c) => c.id === name)) {
      console.log(
        `  [${dryRun ? 'dry' : 'del'}] ${name}: ~${n} doc(s)`,
      );
      wiped.push(name);
      docs += n;
    }
  }
  return { docs, cols: wiped };
}

async function wipeStorageExceptMembros(bucket, churchId) {
  const prefix = `igrejas/${churchId}/`;
  const keepPrefix = `igrejas/${churchId}/membros/`;
  let deleted = 0;
  let pageToken;
  do {
    const [files, , apiResp] = await bucket.getFiles({
      prefix,
      maxResults: 200,
      pageToken,
    });
    pageToken = apiResp && apiResp.nextPageToken;
    const toDelete = files.filter((f) => {
      const n = f.name || '';
      if (!n.startsWith(prefix)) return false;
      if (n.startsWith(keepPrefix)) return false;
      return true;
    });
    if (toDelete.length === 0) continue;
    if (dryRun) {
      deleted += toDelete.length;
      console.log(`  [dry] Storage amostra: ${toDelete.length} ficheiro(s)`);
      break;
    }
    await Promise.all(toDelete.map((f) => f.delete().catch(() => {})));
    deleted += toDelete.length;
    console.log(`  [del] Storage lote: ${toDelete.length}`);
  } while (pageToken && !dryRun);
  return deleted;
}

async function main() {
  const churchId = churchArg
    ? churchArg.split('=')[1].trim()
    : CANONICAL;
  const targets = [churchId];
  if (alsoLegacy) {
    for (const id of LEGACY_IDS) {
      if (!targets.includes(id)) targets.push(id);
    }
  }

  const sa = findSa();
  if (!sa) {
    console.error(
      'Service account não encontrada (ANDROID/*-firebase-adminsdk*.json).',
    );
    process.exit(1);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = sa;
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
    });
  }
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  console.log('=== Limpeza BPC — manter só membros ===');
  console.log(`Modo: ${dryRun ? 'DRY-RUN (use --execute para apagar)' : 'EXECUTE'}`);
  console.log(`Alvos: ${targets.join(', ')}`);
  console.log(`SA: ${sa}`);

  for (const id of targets) {
    console.log(`\n--- igrejas/${id} ---`);
    const fsResult = await wipeChurchSubcollections(db, id);
    console.log(`  Firestore docs tocados: ${fsResult.docs}`);
    const st = await wipeStorageExceptMembros(bucket, id);
    console.log(`  Storage ficheiros: ${st}`);
  }

  console.log('\nConcluído.');
  if (dryRun) {
    console.log('Reexecute com --execute para aplicar.');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
