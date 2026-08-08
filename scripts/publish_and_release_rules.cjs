'use strict';
/**
 * Publica firestore.rules em PRODUCAO:
 *  1) cria ruleset a partir de firestore.rules
 *  2) libera (release) cloud.firestore apontando p/ o novo ruleset
 *  3) verifica que o release ativo aponta p/ o novo ruleset
 * Uso: GOOGLE_APPLICATION_CREDENTIALS=<key> node scripts/publish_and_release_rules.cjs
 */
const fs = require('fs');
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));
const projectId = 'gestaoyahweh-21e23';
const base = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;
const root = path.join(__dirname, '..');

async function main() {
  const { token, source } = await getAccessToken();
  console.log(`token OK (source=${source})`);
  const H = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

  const content = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const bytes = Buffer.byteLength(content, 'utf8');
  console.log(`firestore.rules: ${bytes} bytes, ${content.split('\n').length} linhas`);

  // 1) criar ruleset
  console.log('\n1) criando ruleset...');
  const t0 = Date.now();
  const cr = await fetch(`${base}/rulesets`, {
    method: 'POST', headers: H,
    body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content }] } }),
  });
  const crText = await cr.text();
  if (!cr.ok) { console.error(`FALHOU criar ruleset: ${cr.status} ${crText}`); process.exit(1); }
  const ruleset = JSON.parse(crText);
  console.log(`   ruleset criado: ${ruleset.name} em ${Date.now() - t0}ms`);

  // 2) liberar release (PATCH atualiza o existente)
  console.log('\n2) liberando release cloud.firestore...');
  const relName = `projects/${projectId}/releases/cloud.firestore`;
  let rel = await fetch(`${base}/releases?updateMask=rulesetName`, {
    method: 'PATCH', headers: H,
    body: JSON.stringify({ release: { name: relName, rulesetName: ruleset.name } }),
  });
  let relText = await rel.text();
  if (!rel.ok) {
    // fallback: alguns backends usam PATCH em /releases/cloud.firestore
    console.log(`   PATCH /releases falhou (${rel.status}), tentando PATCH direto no release...`);
    rel = await fetch(`${base}/releases/cloud.firestore`, {
      method: 'PATCH', headers: H,
      body: JSON.stringify({ name: relName, rulesetName: ruleset.name }),
    });
    relText = await rel.text();
  }
  if (!rel.ok) { console.error(`FALHOU liberar release: ${rel.status} ${relText}`); process.exit(1); }
  console.log(`   release atualizado.`);

  // 3) verificar
  console.log('\n3) verificando release ativo...');
  const chk = await fetch(`${base}/releases/cloud.firestore`, { headers: H });
  const active = JSON.parse(await chk.text());
  console.log(`   rulesetName ativo: ${active.rulesetName}`);
  console.log(`   updateTime: ${active.updateTime}`);
  if (active.rulesetName === ruleset.name) {
    console.log('\n✅ SUCESSO: produção agora usa o ruleset v4 enxuto.');
  } else {
    console.error('\n⚠️ Release ativo NAO corresponde ao ruleset recem-criado. Verificar manualmente.');
    process.exit(1);
  }
}
main().catch((e) => { console.error('fatal:', e.message); process.exit(1); });
