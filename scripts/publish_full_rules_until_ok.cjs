/**
 * Republica o firestore.rules COMPLETO assim que o backend de compilacao do
 * Google (firebaserules.googleapis.com) voltar a responder dentro do deadline.
 *
 * Contexto: quando o backend esta degradado, rulesets complexos retornam 503
 * (UNAVAILABLE) apos ~5-7s (timeout de compilacao), enquanto rulesets triviais
 * compilam em ~1s. Nao e o nosso codigo (a versao de ontem tambem falha agora).
 * A unica correcao e reentar ate o servico acelerar.
 *
 * Loop: cria ruleset (full) -> se OK, aponta a release cloud.firestore e sai(0).
 * Em 503/429/504, aguarda ~90s (+jitter) e tenta de novo, ate MAX_MINUTES.
 *
 * Uso: node scripts/publish_full_rules_until_ok.cjs
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));

const projectId = 'gestaoyahweh-21e23';
const base = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;
const root = path.join(__dirname, '..');
const releaseName = `projects/${projectId}/releases/cloud.firestore`;
const encodedRelease = encodeURIComponent('cloud.firestore');

const MAX_MINUTES = 180;          // desiste depois de 3h
const WAIT_BASE_MS = 90 * 1000;   // ~90s entre tentativas

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
function ts() { return new Date().toISOString().substring(11, 19); }

async function patchRelease(rulesetName, token) {
  const bodies = [
    { release: { name: releaseName, rulesetName } },
    { name: releaseName, rulesetName },
  ];
  for (const body of bodies) {
    const res = await fetch(`${base}/releases/${encodedRelease}?updateMask=rulesetName`, {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (res.ok) return true;
    const d = await res.text();
    console.log(`[${ts()}] PATCH status ${res.status}: ${d.substring(0, 200)}`);
  }
  return false;
}

async function main() {
  const full = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const bytes = Buffer.byteLength(full, 'utf8');
  const deadline = Date.now() + MAX_MINUTES * 60 * 1000;
  let attempt = 0;
  console.log(`[${ts()}] Republicar FULL (${bytes}B) ate o backend do Google recuperar. Limite ${MAX_MINUTES}min.`);

  while (Date.now() < deadline) {
    attempt++;
    let token;
    try { token = (await getAccessToken()).token; }
    catch (e) { console.log(`[${ts()}] auth erro: ${e.message}; retry.`); await sleep(30000); continue; }

    const t0 = Date.now();
    let res;
    try {
      res = await fetch(base + '/rulesets', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content: full }] } }),
      });
    } catch (e) {
      console.log(`[${ts()}] #${attempt} rede erro em ${Date.now() - t0}ms: ${e.message}`);
      await sleep(WAIT_BASE_MS); continue;
    }
    const ms = Date.now() - t0;
    const data = await res.json().catch(() => ({}));

    if (res.ok && data.name) {
      console.log(`[${ts()}] #${attempt} ruleset criado em ${ms}ms: ${data.name} — publicando release...`);
      const ok = await patchRelease(data.name, token);
      if (ok) {
        console.log(`[${ts()}] >>> SUCESSO: firestore.rules COMPLETO publicado e ativo em producao.`);
        process.exit(0);
      }
      console.log(`[${ts()}] #${attempt} ruleset criado mas PATCH release falhou; retry.`);
      await sleep(20000); continue;
    }

    const code = (data.error && data.error.status) || res.status;
    console.log(`[${ts()}] #${attempt} 503/timeout compilacao (status ${res.status}/${code}) em ${ms}ms; aguardar...`);
    const jitter = Math.floor(Math.random() * 25000);
    await sleep(WAIT_BASE_MS + jitter);
  }

  console.log(`[${ts()}] Esgotado ${MAX_MINUTES}min sem sucesso. Backend do Google ainda degradado. Rode de novo depois.`);
  process.exit(2);
}
main().catch((e) => { console.error('fatal:', e.message); process.exit(1); });
