/**
 * RECON (read-only) da colecao raiz `users/{uid}` — cobertura de campos que
 * as regras usam para resolver papel/tenant/identidade.
 * NAO ESCREVE NADA.
 */
'use strict';
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');
admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();

async function main() {
  console.log('=== RECON users/{uid} (read-only) ===');
  const snap = await db.collection('users').get();
  console.log(`users docs: ${snap.size}`);
  const fields = ['email', 'cpf', 'CPF', 'cpfDigits', 'linkedCpf', 'memberDocId',
    'igrejaId', 'tenantId', 'churchId', 'churchCanonicalId', 'role', 'roles'];
  const cov = {}; for (const f of fields) cov[f] = 0;
  let idIsUid = 0, hasAnyTenant = 0, hasAnyCpf = 0;
  const noTenantSample = [];
  for (const d of snap.docs) {
    const x = d.data();
    for (const f of fields) {
      if (x[f] !== undefined && x[f] !== null && String(x[f]).length > 0) cov[f]++;
    }
    if (d.id.length >= 20) idIsUid++;
    const tenant = x.igrejaId || x.tenantId || x.churchId || x.churchCanonicalId || x.canonicalTenantId;
    if (tenant) hasAnyTenant++; else if (noTenantSample.length < 8) noTenantSample.push({ id: d.id, email: x.email || null });
    if (x.cpf || x.CPF || x.cpfDigits || x.linkedCpf) hasAnyCpf++;
  }
  console.log('cobertura:', JSON.stringify(cov));
  console.log(`docId parece uid: ${idIsUid}/${snap.size}`);
  console.log(`tem algum campo de tenant: ${hasAnyTenant}/${snap.size}`);
  console.log(`tem algum campo de cpf: ${hasAnyCpf}/${snap.size}`);
  console.log('sem tenant (amostra):', JSON.stringify(noTenantSample));
  process.exit(0);
}
main().catch((e) => { console.error('ERRO:', e.message); process.exit(1); });
