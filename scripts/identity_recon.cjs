/**
 * RECON (somente leitura) para o projeto de padronizacao de identidade
 * (authUid + cpf + email) em membros/usuarios.
 *
 * NAO ESCREVE NADA. Apenas mede escala e formato dos dados:
 *  - total de usuarios no Firebase Auth (uid + email)
 *  - total de igrejas (tenants)
 *  - por igreja (amostra): quantos membros, e cobertura de campos
 *    (authUid/firebaseUid/EMAIL/email/CPF/cpf) para desenhar o match.
 *
 * Uso: node scripts/identity_recon.cjs
 */
'use strict';
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');

admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();
const auth = admin.auth();

async function countAuthUsers() {
  let total = 0, withEmail = 0, next;
  const sample = [];
  do {
    const res = await auth.listUsers(1000, next);
    for (const u of res.users) {
      total++;
      if (u.email) withEmail++;
      if (sample.length < 5) sample.push({ uid: u.uid, email: u.email || null });
    }
    next = res.pageToken;
  } while (next);
  return { total, withEmail, sample };
}

function fieldCoverage(docs, fields) {
  const cov = {};
  for (const f of fields) cov[f] = 0;
  for (const d of docs) {
    const data = d.data();
    for (const f of fields) {
      if (data[f] !== undefined && data[f] !== null && String(data[f]).length > 0) cov[f]++;
    }
  }
  return cov;
}

async function main() {
  console.log('=== RECON identidade (read-only) ===');
  const a = await countAuthUsers();
  console.log(`AUTH: ${a.total} usuarios (com email: ${a.withEmail})`);
  console.log('  amostra:', JSON.stringify(a.sample));

  const igrejasSnap = await db.collection('igrejas').get();
  console.log(`\nIGREJAS: ${igrejasSnap.size} tenants`);

  const memberFields = ['authUid', 'firebaseUid', 'EMAIL', 'email', 'CPF', 'cpf', 'cpfDigits', 'MEMBER_ID', 'role', 'FUNCAO'];
  let shown = 0;
  let totalMembros = 0;
  for (const ig of igrejasSnap.docs) {
    const membrosSnap = await db.collection('igrejas').doc(ig.id).collection('membros').get();
    totalMembros += membrosSnap.size;
    if (shown < 3 && membrosSnap.size > 0) {
      shown++;
      const cov = fieldCoverage(membrosSnap.docs, memberFields);
      console.log(`\n  [${ig.id}] membros=${membrosSnap.size}`);
      console.log('    cobertura campos:', JSON.stringify(cov));
      // ids: quantos docId parecem uid vs cpf(11 digitos)
      let idUid = 0, idCpf = 0, idOutro = 0;
      for (const m of membrosSnap.docs) {
        if (/^[0-9]{11}$/.test(m.id)) idCpf++;
        else if (m.id.length >= 20) idUid++;
        else idOutro++;
      }
      console.log(`    docId: ~uid=${idUid} cpf11=${idCpf} outro=${idOutro}`);
    }
  }
  console.log(`\nTOTAL MEMBROS (todas igrejas): ${totalMembros}`);
  console.log('=== fim recon ===');
  process.exit(0);
}
main().catch((e) => { console.error('ERRO recon:', e.message); process.exit(1); });
