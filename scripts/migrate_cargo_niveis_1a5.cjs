// Migra o `hierarchyLevel` dos cargos de TODAS as igrejas da escala antiga
// (0-100: 100, 88, 72, 65, 55, 12) para a escala nova de 1 a 5.
//
//   100 / 88  -> 5  pastor presidente, gestor, adm e pastor auxiliar
//   72        -> 3  secretario(a)
//   65        -> 4  tesoureiro(a)
//   55        -> 2  lider de departamento
//   resto     -> 1  membro / congregado
//
// A conversao preserva a ordem de quem podia mais — nenhuma igreja ganha ou
// perde acesso por causa da migracao. Valores que ja estao entre 1 e 5 ficam
// como estao (o script pode correr as vezes que forem precisas).
//
// Uso:  node scripts/migrate_cargo_niveis_1a5.cjs [--dry]
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');

const DRY = process.argv.includes('--dry');

admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();

function nivelNovo(bruto) {
  const v = Number.isFinite(bruto) ? bruto : 1;
  if (v >= 1 && v <= 5) return v;
  if (v >= 80) return 5;
  if (v >= 66) return 3;
  if (v >= 60) return 4;
  if (v >= 40) return 2;
  return 1;
}

(async () => {
  const igrejas = await db.collection('igrejas').get();
  console.log(`Igrejas: ${igrejas.size}${DRY ? '  (SIMULACAO — nada e gravado)' : ''}`);

  let totalCargos = 0;
  let totalConvertidos = 0;

  for (const igreja of igrejas.docs) {
    const cargos = await igreja.ref.collection('cargos').get();
    if (cargos.empty) continue;

    const alteracoes = [];
    for (const cargo of cargos.docs) {
      totalCargos += 1;
      const atual = Number((cargo.data() || {}).hierarchyLevel);
      const novo = nivelNovo(atual);
      if (atual === novo) continue;
      alteracoes.push({ ref: cargo.ref, id: cargo.id, atual, novo });
    }

    if (!alteracoes.length) {
      console.log(`  ${igreja.id}: ${cargos.size} cargo(s), nada a converter`);
      continue;
    }

    console.log(`  ${igreja.id}: ${alteracoes.length} de ${cargos.size} cargo(s)`);
    for (const a of alteracoes) {
      console.log(`     ${a.id}: ${Number.isFinite(a.atual) ? a.atual : '(vazio)'} -> ${a.novo}`);
    }

    if (!DRY) {
      const lote = db.batch();
      for (const a of alteracoes) {
        lote.set(a.ref, {
          hierarchyLevel: a.novo,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      await lote.commit();
    }
    totalConvertidos += alteracoes.length;
  }

  console.log(`\nOK: ${totalConvertidos} de ${totalCargos} cargo(s) na escala 1-5.`);
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e); process.exit(1); });
