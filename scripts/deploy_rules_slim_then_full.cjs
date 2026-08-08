/**
 * Deploy de regras Firestore: COMPACT (slim) primeiro para destravar a API
 * (firebaserules.googleapis.com), depois a FULL completa.
 *
 * Motivacao: com a rules API instavel (503/400), publicar o ruleset menor
 * (firestore.rules.slim, ~74KB, MESMA seguranca minificada) tende a passar,
 * deixando regras validas e seguras ativas; em seguida promovemos a FULL.
 *
 * Uso:  node scripts/deploy_rules_slim_then_full.cjs
 * Se a FULL falhar apos os retries, o slim (seguro) permanece ativo e o
 * script sai com codigo 2 (parcial) para o orquestrador saber que deve
 * repetir so a FULL depois.
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

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function freshToken() {
  const auth = await getAccessToken();
  return auth.token;
}

// Cria um ruleset (POST /rulesets) com retry em 503/429/504. Retorna o name.
async function createRuleset(label, content, maxAttempts) {
  const backoff = [8, 15, 25, 40, 60, 90, 120, 150];
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const token = await freshToken();
    process.stdout.write(`[${label}] criar ruleset (tentativa ${attempt}/${maxAttempts}, ${content.length} bytes)... `);
    let res;
    try {
      res = await fetch(base + '/rulesets', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content }] } }),
      });
    } catch (e) {
      console.log(`erro rede: ${e.message}`);
      await sleep((backoff[Math.min(attempt - 1, backoff.length - 1)]) * 1000);
      continue;
    }
    console.log(`status ${res.status}`);
    const data = await res.json().catch(() => ({}));
    if (res.ok && data.name) {
      console.log(`[${label}] OK ruleset: ${data.name}`);
      return data.name;
    }
    const msg = JSON.stringify(data).substring(0, 400);
    if (res.status === 503 || res.status === 429 || res.status === 504) {
      console.log(`[${label}] API indisponivel (${res.status}); retry. ${msg}`);
      await sleep((backoff[Math.min(attempt - 1, backoff.length - 1)]) * 1000);
      continue;
    }
    // 400 e outros: erro possivelmente de payload/compilacao — mostrar e abortar esta fase.
    console.log(`[${label}] erro nao-transiente (${res.status}): ${msg}`);
    return null;
  }
  console.log(`[${label}] esgotadas ${maxAttempts} tentativas de criar ruleset.`);
  return null;
}

// Aponta a release cloud.firestore para o ruleset (PATCH). Retorna bool.
async function patchRelease(label, rulesetName, maxAttempts) {
  const backoff = [5, 10, 20, 30, 45, 60];
  const bodies = [
    { release: { name: releaseName, rulesetName } },
    { name: releaseName, rulesetName },
  ];
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const token = await freshToken();
    for (const body of bodies) {
      let res;
      try {
        res = await fetch(`${base}/releases/${encodedRelease}?updateMask=rulesetName`, {
          method: 'PATCH',
          headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
      } catch (e) {
        console.log(`[${label}] PATCH erro rede: ${e.message}`);
        continue;
      }
      if (res.ok) {
        console.log(`[${label}] release publicada -> ${rulesetName}`);
        return true;
      }
      const data = await res.json().catch(() => ({}));
      console.log(`[${label}] PATCH status ${res.status}: ${JSON.stringify(data).substring(0, 250)}`);
      if (![503, 429, 504].includes(res.status)) {
        // tentar proximo formato de body na mesma tentativa
        continue;
      }
    }
    await sleep((backoff[Math.min(attempt - 1, backoff.length - 1)]) * 1000);
  }
  return false;
}

async function publishPhase(label, file, rulesetAttempts, releaseAttempts) {
  const filePath = path.join(root, file);
  const content = fs.readFileSync(filePath, 'utf8');
  const name = await createRuleset(label, content, rulesetAttempts);
  if (!name) return false;
  return await patchRelease(label, name, releaseAttempts);
}

async function main() {
  console.log('=== Deploy regras: COMPACT (slim) -> FULL ===');

  // Fase 1: COMPACT — destrava a API com payload menor. Mesma seguranca (minificada).
  const slimOk = await publishPhase('compact', 'firestore.rules.slim', 8, 6);
  if (!slimOk) {
    console.log('\n[compact] FALHOU. API provavelmente indisponivel; nada publicado por esta fase.');
    process.exit(1);
  }
  console.log('\n[compact] >>> Regras COMPACTAS (seguras) ativas em producao. API destravada.');

  // Pequena folga antes de promover a FULL.
  await sleep(4000);

  // Fase 2: FULL — promove a versao completa.
  const fullOk = await publishPhase('full', 'firestore.rules', 8, 6);
  if (!fullOk) {
    console.log('\n[full] FALHOU apos publicar compact. As regras COMPACTAS (seguras) seguem ativas.');
    console.log('[full] Repita depois: node scripts/deploy_rules_slim_then_full.cjs (ou so a FULL).');
    process.exit(2);
  }
  console.log('\n[full] >>> Regras COMPLETAS ativas em producao.');
  console.log('=== OK: compact -> full concluido ===');
  process.exit(0);
}

main().catch((e) => { console.error('ERRO fatal:', e.message); process.exit(1); });
