'use strict';
/**
 * Testa qual tamanho de ruleset o backend aceita AGORA (durante o 503).
 * Cria (nao libera) tiny -> v4 -> full e mede status/tempo.
 */
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

async function tryCreate(label, content, H) {
  const bytes = Buffer.byteLength(content, 'utf8');
  const t0 = Date.now();
  let res, text;
  try {
    res = await fetch(`${base}/rulesets`, {
      method: 'POST', headers: H,
      body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content }] } }),
    });
    text = await res.text();
  } catch (e) {
    console.log(`[${label}] ${bytes}B -> ERRO REDE ${Date.now() - t0}ms: ${e.message}`);
    return null;
  }
  const ms = Date.now() - t0;
  const ra = res.headers.get('retry-after');
  if (res.ok) {
    const j = JSON.parse(text);
    console.log(`[${label}] ${bytes}B -> 200 OK em ${ms}ms  ruleset=${j.name.split('/').pop()}`);
    return j.name;
  }
  console.log(`[${label}] ${bytes}B -> ${res.status} em ${ms}ms${ra ? ' Retry-After=' + ra : ''}  body=${text.substring(0, 300).replace(/\s+/g, ' ')}`);
  return null;
}

async function main() {
  const { token } = await getAccessToken();
  const H = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  await tryCreate('TINY', tiny, H);
  const v4Path = path.join(root, 'firestore.rules.v4');
  if (fs.existsSync(v4Path)) await tryCreate('V4', fs.readFileSync(v4Path, 'utf8'), H);
  const fullPath = path.join(root, 'firestore.rules');
  if (fs.existsSync(fullPath)) await tryCreate('FULL', fs.readFileSync(fullPath, 'utf8'), H);
  console.log('=== fim ===');
}
main().catch((e) => { console.error('fatal:', e.message); process.exit(1); });
