'use strict';
/**
 * Verifica o estado operacional das regras Firestore:
 *  1) Qual ruleset esta ATIVO em producao (release cloud.firestore) + tamanho/conteudo.
 *  2) Se o backend do Google ja compila (saiu do 503): tenta CRIAR um ruleset a
 *     partir de firestore.rules (sem liberar/release) e mede tempo.
 * Nao altera producao. Somente leitura + teste de compilacao.
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

  // 1) Release ativo
  console.log('\n===== RELEASE ATIVO (producao) =====');
  const relRes = await fetch(`${base}/releases/cloud.firestore`, { headers: H });
  console.log(`releases/cloud.firestore -> status ${relRes.status}`);
  const relText = await relRes.text();
  if (relRes.ok) {
    const rel = JSON.parse(relText);
    const rulesetName = rel.rulesetName;
    console.log(`rulesetName ativo: ${rulesetName}`);
    console.log(`updateTime: ${rel.updateTime}`);
    // Buscar conteudo do ruleset ativo
    const rsRes = await fetch(`https://firebaserules.googleapis.com/v1/${rulesetName}`, { headers: H });
    if (rsRes.ok) {
      const rs = JSON.parse(await rsRes.text());
      const files = (rs.source && rs.source.files) || [];
      for (const f of files) {
        const bytes = Buffer.byteLength(f.content, 'utf8');
        const lines = f.content.split('\n').length;
        const hasAllow = /allow\s+(read|write|get|list|create|update|delete)/.test(f.content);
        console.log(`  file ${f.name}: ${bytes} bytes, ${lines} linhas, contem 'allow ...': ${hasAllow}`);
        // Heuristica: ruleset deny-all minimo?
        const isDenyAll = bytes < 2000 && !hasAllow || /allow read, write: if false;\s*}\s*}\s*}\s*$/.test(f.content.trim()) && lines < 20;
        console.log(`  -> parece ruleset MINIMO/deny-all? ${bytes < 1500 ? 'SIM (pequeno)' : 'NAO (parece completo)'}`);
      }
    } else {
      console.log(`  falha ao buscar conteudo do ruleset: ${rsRes.status} ${await rsRes.text()}`);
    }
  } else {
    console.log(`body: ${relText.substring(0, 800)}`);
  }

  // 2) Health check do compilador: criar ruleset a partir de firestore.rules
  console.log('\n===== HEALTH CHECK: compilar firestore.rules (NAO libera) =====');
  const fullPath = path.join(root, 'firestore.rules');
  if (!fs.existsSync(fullPath)) {
    console.log('firestore.rules nao encontrado na raiz.');
  } else {
    const full = fs.readFileSync(fullPath, 'utf8');
    console.log(`firestore.rules: ${Buffer.byteLength(full, 'utf8')} bytes, ${full.split('\n').length} linhas`);
    const t0 = Date.now();
    const res = await fetch(`${base}/rulesets`, {
      method: 'POST', headers: H,
      body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content: full }] } }),
    });
    const ms = Date.now() - t0;
    console.log(`POST /rulesets -> status ${res.status} em ${ms}ms`);
    const ra = res.headers.get('retry-after');
    if (ra) console.log(`Retry-After: ${ra}`);
    const text = await res.text();
    if (res.ok) {
      const j = JSON.parse(text);
      console.log(`OK! ruleset criado: ${j.name} (backend SAUDAVEL, saiu do 503)`);
      console.log('(ruleset criado mas NAO liberado; pode ser deletado ou usado no publish)');
    } else {
      console.log(`FALHOU: ${text.substring(0, 800)}`);
    }
  }
  console.log('\n=== fim ===');
}
main().catch((e) => { console.error('fatal:', e.message); process.exit(1); });
