#!/usr/bin/env node
/**
 * Migração: doc raiz igrejas + church_aliases + pastas Storage igrejas/{tenantId}/…
 *
 * Uso (na raiz do repo):
 *   node scripts/migrate_church_roots_and_aliases.mjs
 *   node scripts/migrate_church_roots_and_aliases.mjs --dry-run
 *   node scripts/migrate_church_roots_and_aliases.mjs --id=igreja_o_brasil_para_cristo_jardim_goiano
 *
 * Credencial: GOOGLE_APPLICATION_CREDENTIALS ou serviceAccountKey.json na raiz.
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

const BPC_CANONICAL = 'igreja_o_brasil_para_cristo_jardim_goiano';
const ANCHORED = {
  [BPC_CANONICAL]: [
    BPC_CANONICAL,
    'brasilparacristo',
    'brasilparacristo_sistema',
    'iobpc-jardim-goiano',
    'o-brasil-cristo-jardim-goiano',
  ],
};

const MIN_PNG = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48,
  0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
  0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78,
  0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const onlyId = args.find((a) => a.startsWith('--id='))?.split('=')[1]?.trim() || '';

function initAdmin() {
  if (getApps().length) return;
  const saPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    resolve(root, 'serviceAccountKey.json');
  if (!existsSync(saPath)) {
    console.error('Credencial não encontrada:', saPath);
    console.error('Defina GOOGLE_APPLICATION_CREDENTIALS ou coloque serviceAccountKey.json na raiz.');
    process.exit(1);
  }
  const sa = JSON.parse(readFileSync(saPath, 'utf8'));
  const projectId = sa.project_id || 'gestaoyahweh-21e23';
  const storageBucket =
    process.env.FIREBASE_STORAGE_BUCKET ||
    `${projectId}.firebasestorage.app`;
  initializeApp({
    credential: cert(sa),
    projectId,
    storageBucket,
  });
}

function storageBucket() {
  const app = getApps()[0];
  const id = app?.options?.storageBucket || 'gestaoyahweh-21e23.firebasestorage.app';
  return getStorage().bucket(id);
}

function resolveCanonical(id) {
  const t = String(id || '').trim();
  if (!t) return t;
  for (const [canonical, members] of Object.entries(ANCHORED)) {
    if (t === canonical || members.includes(t)) return canonical;
  }
  return t;
}

function slugHintFromDocId(docId) {
  let s = String(docId || '').trim();
  if (!s) return '';
  if (s.startsWith('igreja_')) s = s.slice('igreja_'.length);
  return s.replace(/_/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
}

function collectAliases(docId, data) {
  const canonical = resolveCanonical(docId);
  const out = new Set();
  const add = (v) => {
    const t = String(v || '').trim();
    if (t && t !== canonical) out.add(t);
  };
  for (const k of ['slug', 'slugId', 'alias', 'churchId', 'igrejaId', 'tenantId']) {
    add(data?.[k]);
  }
  add(docId);
  const hint = slugHintFromDocId(docId);
  if (hint) add(hint);
  for (const m of ANCHORED[canonical] || []) add(m);
  return { canonical, aliases: [...out] };
}

function buildRootPatch(docId, data) {
  const canonical = resolveCanonical(docId);
  const patch = {};
  const nome =
    String(data?.nome || data?.name || '').trim() ||
    docId.replace(/^igreja_/, '').replace(/_/g, ' ').trim() ||
    docId;

  if (!String(data?.nome || '').trim()) patch.nome = nome;
  if (!String(data?.name || '').trim()) patch.name = nome;
  if (!String(data?.tenantId || '').trim()) patch.tenantId = canonical;
  if (!String(data?.igrejaId || '').trim()) patch.igrejaId = canonical;
  if (!String(data?.churchId || '').trim()) patch.churchId = canonical;

  const slug =
    String(data?.slug || data?.slugId || data?.alias || '').trim() ||
    slugHintFromDocId(docId);
  if (slug) {
    if (!String(data?.slug || '').trim()) patch.slug = slug;
    if (!String(data?.slugId || '').trim()) patch.slugId = slug;
    if (!String(data?.alias || '').trim()) patch.alias = slug;
  }
  if (data?.ativa === undefined && data?.active === undefined) patch.ativa = true;
  if (!data?.status) patch.status = 'ativa';
  patch.tenantProvisionedAt = FieldValue.serverTimestamp();
  patch.tenantProvisionSource = 'migrate_church_roots_and_aliases.mjs';
  return patch;
}

async function ensureStoragePlaceholders(canonical, dry) {
  const bucket = storageBucket();
  const png = `igrejas/${canonical}/configuracoes/logo_igreja.png`;
  const fin = `igrejas/${canonical}/financeiro/_structure/placeholder.png`;
  let configCreated = false;
  let finCreated = false;

  for (const path of [png, fin]) {
    const file = bucket.file(path);
    const [exists] = await file.exists();
    if (exists) continue;
    if (dry) {
      console.log(`  [dry-run] Storage PUT ${path}`);
      if (path.includes('configuracoes')) configCreated = true;
      else finCreated = true;
      continue;
    }
    await file.save(MIN_PNG, {
      contentType: 'image/png',
      resumable: false,
      metadata: { cacheControl: 'public,max-age=60' },
    });
    if (path.includes('configuracoes')) configCreated = true;
    else finCreated = true;
  }
  return { configCreated, finCreated };
}

async function provisionOne(db, docId, dry) {
  const ref = db.collection('igrejas').doc(docId);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() || {} : {};
  const patch = buildRootPatch(docId, data);
  const { canonical, aliases } = collectAliases(docId, { ...data, ...patch });

  console.log(`\n▶ ${docId} → canónico ${canonical}`);
  if (!snap.exists) {
    console.log('  ⏭ doc raiz fantasma — NÃO criar (evita ressuscitar igrejas teste)');
    return { docId, canonical, aliases: 0, ok: true, skippedGhost: true };
  }

  if (dry) {
    console.log('  [dry-run] root patch:', JSON.stringify(patch, null, 2));
    console.log(`  [dry-run] aliases (${aliases.length}):`, aliases.join(', '));
  } else {
    await ref.set(patch, { merge: true });
    const batch = db.batch();
    for (const alias of aliases) {
      batch.set(
        db.collection('church_aliases').doc(alias),
        {
          canonicalId: canonical,
          alias,
          updatedAt: FieldValue.serverTimestamp(),
          source: 'migrate_church_roots_and_aliases.mjs',
        },
        { merge: true },
      );
    }
    await batch.commit();
    console.log(`  ✓ root + ${aliases.length} alias(es)`);
  }

  const st = await ensureStoragePlaceholders(canonical, dry);
  if (st.configCreated || st.finCreated) {
    console.log(
      `  ✓ Storage: config=${st.configCreated ? 'criado' : 'ok'} financeiro=${st.finCreated ? 'criado' : 'ok'}`,
    );
  }

  return { docId, canonical, aliases: aliases.length, ok: true };
}

async function main() {
  initAdmin();
  const db = getFirestore();

  let ids;
  if (onlyId) {
    ids = [onlyId];
  } else {
    const refs = await db.collection('igrejas').listDocuments();
    ids = refs.map((r) => r.id).filter(Boolean);
  }

  console.log(`Migração igrejas (${ids.length} doc(s))${dryRun ? ' [DRY-RUN]' : ''}`);

  const results = [];
  for (const id of ids) {
    try {
      results.push(await provisionOne(db, id, dryRun));
    } catch (e) {
      console.error(`  ✗ ${id}:`, e?.message || e);
      results.push({ docId: id, ok: false });
    }
  }

  const ok = results.filter((r) => r.ok).length;
  console.log(`\nConcluído: ${ok}/${results.length} igreja(s).`);
  if (dryRun) console.log('Execute sem --dry-run para aplicar.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
