/**
 * Backfill de identidade canonica (authUid + cpf + email) — ADITIVO e SEGURO.
 *
 * Preenche APENAS campos que faltam, copiando de fontes ja existentes no
 * proprio documento. NUNCA transforma/sobrescreve valores existentes nem
 * adivinha match contra o Auth (usa authUid ja gravado / docId=uid).
 *
 *   membros/{id}:
 *     - email (minusculo)  <- email || EMAIL   (verbatim; e tambem versao .lower())
 *     - cpf   (minusculo)  <- cpf || CPF || cpfDigits  (so grava se der 11 digitos)
 *     - authUid            <- authUid || firebaseUid || (docId se parecer uid)
 *   users/{uid}:
 *     - authUid            <- authUid || docId(uid)
 *     (email/cpf ja cobertos)
 *
 * Modo padrao = DRY-RUN (nao grava). Para aplicar: node ... --apply
 */
'use strict';
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');
admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');
const onlyDigits = (s) => String(s || '').replace(/\D/g, '');
const looksUid = (s) => typeof s === 'string' && s.length >= 20 && !/^[0-9]{11}$/.test(s);

const stats = { membros: { scan: 0, email: 0, cpf: 0, authUid: 0, cpfBadFormat: 0 },
                users: { scan: 0, authUid: 0 },
                tenantUsers: { scan: 0, authUid: 0, igrejaId: 0 } };
const samples = [];

async function processMembros() {
  const igrejas = await db.collection('igrejas').get();
  for (const ig of igrejas.docs) {
    const membros = await db.collection('igrejas').doc(ig.id).collection('membros').get();
    for (const m of membros.docs) {
      stats.membros.scan++;
      const d = m.data();
      const patch = {};
      // email minusculo
      const emailSrc = (typeof d.email === 'string' && d.email) ? d.email
        : (typeof d.EMAIL === 'string' ? d.EMAIL : '');
      if (!d.email && emailSrc) patch.email = emailSrc;
      // cpf minusculo (so 11 digitos)
      if (!d.cpf) {
        const digits = onlyDigits(d.cpf || d.CPF || d.cpfDigits);
        if (digits.length === 11) patch.cpf = digits;
        else if (d.CPF || d.cpfDigits) stats.membros.cpfBadFormat++;
      }
      // authUid
      if (!d.authUid) {
        const uid = (typeof d.firebaseUid === 'string' && looksUid(d.firebaseUid)) ? d.firebaseUid
          : (looksUid(m.id) ? m.id : '');
        if (uid) patch.authUid = uid;
      }
      if (Object.keys(patch).length) {
        if (patch.email) stats.membros.email++;
        if (patch.cpf) stats.membros.cpf++;
        if (patch.authUid) stats.membros.authUid++;
        if (samples.length < 12) samples.push({ path: `igrejas/${ig.id}/membros/${m.id}`, patch });
        if (APPLY) await m.ref.set(patch, { merge: true });
      }
    }
  }
}

async function processUsers() {
  const users = await db.collection('users').get();
  for (const u of users.docs) {
    stats.users.scan++;
    const d = u.data();
    const patch = {};
    if (!d.authUid && looksUid(u.id)) patch.authUid = u.id;
    if (Object.keys(patch).length) {
      stats.users.authUid++;
      if (samples.length < 24) samples.push({ path: `users/${u.id}`, patch });
      if (APPLY) await u.ref.set(patch, { merge: true });
    }
  }
}

async function processTenantUsers() {
  const igrejas = await db.collection('igrejas').get();
  for (const ig of igrejas.docs) {
    const us = await db.collection('igrejas').doc(ig.id).collection('users').get();
    for (const u of us.docs) {
      stats.tenantUsers.scan++;
      const d = u.data();
      const patch = {};
      if (!d.authUid && looksUid(u.id)) patch.authUid = u.id;
      if (!d.igrejaId) patch.igrejaId = ig.id;
      if (Object.keys(patch).length) {
        if (patch.authUid) stats.tenantUsers.authUid++;
        if (patch.igrejaId) stats.tenantUsers.igrejaId++;
        if (samples.length < 30) samples.push({ path: `igrejas/${ig.id}/users/${u.id}`, patch });
        if (APPLY) await u.ref.set(patch, { merge: true });
      }
    }
  }
}

async function main() {
  console.log(`=== BACKFILL identidade (${APPLY ? 'APLICAR (grava!)' : 'DRY-RUN (nao grava)'}) ===`);
  await processMembros();
  await processUsers();
  await processTenantUsers();
  console.log('membros:', JSON.stringify(stats.membros));
  console.log('users:', JSON.stringify(stats.users));
  console.log('tenantUsers:', JSON.stringify(stats.tenantUsers));
  console.log('\namostra de patches propostos:');
  for (const s of samples) console.log('  ', s.path, '->', JSON.stringify(s.patch));
  console.log(`\n=== fim (${APPLY ? 'APLICADO' : 'DRY-RUN'}) ===`);
  process.exit(0);
}
main().catch((e) => { console.error('ERRO:', e.message); process.exit(1); });
