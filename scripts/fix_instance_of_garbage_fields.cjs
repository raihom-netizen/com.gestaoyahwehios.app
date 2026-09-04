/**
 * Repara campos gravados por engano como TEXTO "Instance of '<classe>'".
 *
 * CAUSA: o sentinel `YahwehFv.deleteField` seguia para o encoder REST genérico
 * (`_toRestValue`), que faz `v.toString()` — o documento ficava com
 * `instagramUrl: "Instance of 'Ohb'"`. Como o campo não estava vazio, o botão
 * «Instagram» aparecia em TODAS as publicações, mesmo sem link.
 *
 * Uso:
 *   GOOGLE_APPLICATION_CREDENTIALS=<chave admin> node scripts/fix_instance_of_garbage_fields.cjs [--apply]
 * Sem `--apply` só lista o que seria removido (dry-run).
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');
admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');
const SUBCOLLECTIONS = ['eventos', 'avisos', 'noticias', 'mural'];

const isGarbage = (v) => typeof v === 'string' && v.trim().startsWith("Instance of");

function garbageFields(data, prefix = '') {
  const out = [];
  for (const [k, v] of Object.entries(data || {})) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (isGarbage(v)) out.push(key);
    else if (v && typeof v === 'object' && !Array.isArray(v) && !v.toDate) {
      out.push(...garbageFields(v, key));
    }
  }
  return out;
}


/// Remove o lixo. Campos de data nao sao apagados: sem `createdAt` o post fica
/// sem ordenacao no feed, por isso sao reconstruidos a partir do proprio doc.
async function applyPatch(doc, data, fields) {
  const patch = {};
  for (const f of fields) {
    if (/^(createdAt|updatedAt|publishedAt|criadoEm)$/.test(f)) {
      const fallback = [data.startAt, data.updatedAt, data.createdAt]
        .find((v) => v && typeof v.toDate === 'function');
      patch[f] = fallback || admin.firestore.Timestamp.now();
    } else {
      patch[f] = admin.firestore.FieldValue.delete();
    }
  }
  await doc.ref.update(patch);
}

(async () => {
  let scanned = 0, fixed = 0;
  const igrejas = await db.collection('igrejas').get();
  for (const ig of igrejas.docs) {
    for (const col of SUBCOLLECTIONS) {
      let snap;
      try { snap = await ig.ref.collection(col).get(); } catch { continue; }
      for (const d of snap.docs) {
        scanned++;
        const data = d.data();
        const bad = garbageFields(data);
        // `createdAt` em falta = o sentinel de servidor foi gravado como texto e
        // depois removido; sem ele o post perde a ordenacao no feed.
        if (!bad.length && !('createdAt' in data)) {
          fixed++;
          console.log(`${APPLY ? 'REPOR' : 'ACHADO'} ${ig.id}/${col}/${d.id} -> createdAt em falta`);
          if (APPLY) await applyPatch(d, data, ['createdAt']);
          continue;
        }
        if (!bad.length) continue;
        fixed++;
        console.log(`${APPLY ? 'LIMPAR' : 'ACHADO'} ${ig.id}/${col}/${d.id} -> ${bad.join(', ')}`);
        if (APPLY) await applyPatch(d, data, bad);
      }
    }
  }
  console.log(`\n${scanned} documentos lidos, ${fixed} com campo corrompido.` +
    (APPLY ? ' Campos removidos.' : ' Rode com --apply para limpar.'));
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
