/**
 * Deploy rules em duas fases:
 * 1) Regra mínima (firestore.rules.min) — para confirmar que o API recuperou
 * 2) Regra completa (firestore.rules) — assim que a mínima passar
 * 3) Storage rules + indexes
 *
 * Retry automático com backoff até conseguir.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { getAccessToken, findCredentialKeyFile, repoRoot } = require('./gcp_rules_auth.cjs');
const { execSync } = require('child_process');

const projectId = 'gestaoyahweh-21e23';
const baseUrl = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function apiCall(method, urlPath, body, token) {
  const url = `${baseUrl}${urlPath}`;
  const res = await fetch(url, {
    method,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

async function deployRuleset(label, rulesContent, fileName) {
  const authResult = await getAccessToken();
  const token = authResult.token || authResult;
  console.log(`[${label}] auth=${authResult.source || 'direct'} | criar ruleset (${fileName}, ${rulesContent.length} bytes)...`);
  
  const res = await apiCall('POST', '/rulesets', {
    source: { files: [{ name: fileName, content: rulesContent }] },
  }, token);
  
  if (!res.ok) {
    return { ok: false, status: res.status, error: res.data.error?.message || JSON.stringify(res.data) };
  }
  
  const rulesetName = res.data.name;
  console.log(`[${label}] ruleset criado: ${rulesetName}`);
  
  // Release
  let releaseName;
  if (label.startsWith('firestore')) {
    releaseName = 'cloud.firestore';
  } else {
    // Storage: resolver nome dinâmico
    const relList = await apiCall('GET', '/releases?pageSize=100', null, token);
    if (relList.ok && relList.data.releases) {
      for (const r of relList.data.releases) {
        if ((r.name || '').includes('firebase.storage')) {
          releaseName = r.name.replace(/^projects\/[^/]+\/releases\//, '');
          break;
        }
      }
    }
    if (!releaseName) {
      releaseName = `firebase.storage/${projectId}.firebasestorage.app`;
    }
  }
  const encodedRelease = encodeURIComponent(releaseName);
  const fullReleaseName = `projects/${projectId}/releases/${releaseName}`;
  
  console.log(`[${label}] publicar release ${releaseName}...`);
  // Tentar 2 formatos de body (compatibilidade com API)
  const patchBodies = [
    { release: { name: fullReleaseName, rulesetName } },
    { name: fullReleaseName, rulesetName },
  ];
  let lastErr;
  for (const patchBody of patchBodies) {
    const relRes = await apiCall('PATCH', `/releases/${encodedRelease}?updateMask=rulesetName`, patchBody, token);
    if (relRes.ok) {
      console.log(`[${label}] ✓ regras publicadas com sucesso!`);
      return { ok: true };
    }
    lastErr = relRes;
    if (relRes.status !== 400) {
      return { ok: false, status: relRes.status, error: relRes.data.error?.message || JSON.stringify(relRes.data) };
    }
  }
  return { ok: false, status: lastErr?.status || 400, error: lastErr?.data?.error?.message || 'patch failed' };
}

async function main() {
  const root = repoRoot;
  const minRules = fs.readFileSync(path.join(root, 'firestore.rules.min'), 'utf8');
  const fullRules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const storageRules = fs.readFileSync(path.join(root, 'storage.rules'), 'utf8');
  
  const maxAttempts = 30;
  let attempt = 0;
  
  // ===== FASE 1: Regra mínima =====
  console.log('\n══════════════════════════════════════');
  console.log('  FASE 1 — Regra mínima (teste API)');
  console.log('══════════════════════════════════════\n');
  
  while (attempt < maxAttempts) {
    attempt++;
    const result = await deployRuleset('firestore-min', minRules, 'firestore.rules');
    if (result.ok) break;
    
    const waitSec = Math.min(60 + attempt * 15, 180);
    console.log(`[firestore-min] ${result.status}/retry ${attempt}/${maxAttempts}, aguardar ${waitSec}s...`);
    if (attempt >= maxAttempts) {
      console.error('[firestore-min] FALHOU após todas as tentativas. API indisponível.');
      process.exit(1);
    }
    await sleep(waitSec * 1000);
  }
  
  // Esperar 30s entre fases
  console.log('\n[Fase 1 OK] Aguardar 30s antes da fase 2...\n');
  await sleep(30000);
  
  // ===== FASE 2: Regra completa =====
  console.log('\n══════════════════════════════════════');
  console.log('  FASE 2 — Regra completa Firestore');
  console.log('══════════════════════════════════════\n');
  
  attempt = 0;
  while (attempt < 10) {
    attempt++;
    const result = await deployRuleset('firestore-full', fullRules, 'firestore.rules');
    if (result.ok) break;
    
    const waitSec = Math.min(60 + attempt * 20, 180);
    console.log(`[firestore-full] ${result.status}/retry ${attempt}/10, aguardar ${waitSec}s...`);
    await sleep(waitSec * 1000);
  }
  
  if (attempt >= 10) {
    console.error('[firestore-full] FALHOU. Regra mínima ficou ativa como fallback seguro.');
    process.exit(1);
  }
  
  // Esperar 30s entre fases
  console.log('\n[Fase 2 OK] Aguardar 30s antes da fase 3...\n');
  await sleep(30000);
  
  // ===== FASE 3: Storage rules =====
  console.log('\n══════════════════════════════════════');
  console.log('  FASE 3 — Storage Rules');
  console.log('══════════════════════════════════════\n');
  
  attempt = 0;
  while (attempt < 10) {
    attempt++;
    const result = await deployRuleset('storage', storageRules, 'storage.rules');
    if (result.ok) break;
    
    const waitSec = Math.min(60 + attempt * 20, 180);
    console.log(`[storage] ${result.status}/retry ${attempt}/10, aguardar ${waitSec}s...`);
    await sleep(waitSec * 1000);
  }
  
  // ===== FASE 4: Firestore indexes via CLI =====
  console.log('\n══════════════════════════════════════');
  console.log('  FASE 4 — Firestore Indexes');
  console.log('══════════════════════════════════════\n');
  
  try {
    console.log('[indexes] firebase deploy --only firestore:indexes...');
    execSync('npx firebase deploy --only firestore:indexes --project gestaoyahweh-21e23 --non-interactive', {
      cwd: root,
      stdio: 'inherit',
      timeout: 120000,
    });
    console.log('[indexes] ✓ índices publicados!');
  } catch (e) {
    console.log('[indexes] CLI falhou, tentar novamente depois...');
  }
  
  console.log('\n✅ TODAS AS REGRAS PUBLICADAS COM SUCESSO!\n');
}

main().catch(e => { console.error(e); process.exit(1); });
