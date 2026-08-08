/**
 * Diagnostico: por que o ruleset COMPLETO falha e o pequeno passa?
 * Testa 3 payloads na mesma execucao (tiny / slim / full) contra
 * firebaserules.googleapis.com/rulesets e imprime status + corpo completo.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));

const projectId = 'gestaoyahweh-21e23';
const base = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;
const root = path.join(__dirname, '..');

const tiny = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} { allow read, write: if false; }
  }
}`;

async function tryCreate(label, content, token) {
  console.log(`\n===== ${label} (${Buffer.byteLength(content, 'utf8')} bytes) =====`);
  const t0 = Date.now();
  let res;
  try {
    res = await fetch(base + '/rulesets', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content }] } }),
    });
  } catch (e) {
    console.log(`[${label}] erro rede em ${Date.now() - t0}ms: ${e.message}`);
    return;
  }
  const ms = Date.now() - t0;
  console.log(`[${label}] status ${res.status} em ${ms}ms`);
  const ra = res.headers.get('retry-after');
  if (ra) console.log(`[${label}] Retry-After: ${ra}`);
  const text = await res.text();
  console.log(`[${label}] body: ${text.substring(0, 1500)}`);
}

async function main() {
  const { token } = await getAccessToken();
  console.log('token obtido, iniciando testes...');
  await tryCreate('TINY (deny-all valido)', tiny, token);
  const slim = fs.readFileSync(path.join(root, 'firestore.rules.slim'), 'utf8');
  await tryCreate('SLIM', slim, token);
  const full = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  await tryCreate('FULL', full, token);
  console.log('\n=== fim diagnostico ===');
}
main().catch((e) => { console.error('fatal:', e.message); process.exit(1); });
