/**
 * Retry persistente para deploy das regras completas.
 * A regra mínima já está publicada. Este script tenta a completa em loop.
 * 
 * Uso: node scripts/retry_full_rules_deploy.cjs
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));

const projectId = 'gestaoyahweh-21e23';
const base = 'https://firebaserules.googleapis.com/v1/projects/' + projectId;
const root = path.join(__dirname, '..');

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function tryDeployRules(label, content, fileName) {
  let auth;
  try { auth = await getAccessToken(); } catch (e) {
    console.log('[' + label + '] auth error: ' + e.message);
    return false;
  }
  const token = auth.token;
  
  console.log('[' + label + '] criar ruleset (' + fileName + ', ' + content.length + ' bytes)...');
  
  const res = await fetch(base + '/rulesets', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: { files: [{ name: fileName, content }] } }),
  });
  
  if (!res.ok) {
    const data = await res.json().catch(function() { return {}; });
    console.log('[' + label + '] ' + res.status + ': ' + (data.error && data.error.message || 'unknown'));
    return false;
  }
  
  const data = await res.json();
  const rulesetName = data.name;
  console.log('[' + label + '] ruleset: ' + rulesetName);
  
  // Patch release
  var releaseName = label.indexOf('firestore') >= 0 ? 'cloud.firestore' : 'firebase.storage/' + projectId + '.firebasestorage.app';
  var encodedRelease = encodeURIComponent(releaseName);
  var fullReleaseName = 'projects/' + projectId + '/releases/' + releaseName;
  
  console.log('[' + label + '] patch release ' + releaseName + '...');
  var patchBodies = [
    { release: { name: fullReleaseName, rulesetName: rulesetName } },
    { name: fullReleaseName, rulesetName: rulesetName },
  ];
  
  for (var i = 0; i < patchBodies.length; i++) {
    var patchRes = await fetch(base + '/releases/' + encodedRelease + '?updateMask=rulesetName', {
      method: 'PATCH',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify(patchBodies[i]),
    });
    
    if (patchRes.ok) {
      console.log('[' + label + '] DEPLOYADO COM SUCESSO!');
      return true;
    }
    
    var patchData = await patchRes.json().catch(function() { return {}; });
    if (patchRes.status !== 400) {
      console.log('[' + label + '] PATCH ' + patchRes.status + ': ' + (patchData.error && patchData.error.message || 'unknown'));
      return false;
    }
  }
  
  console.log('[' + label + '] PATCH falhou com todos os formatos');
  return false;
}

async function main() {
  var fullRules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  var storageRules = fs.readFileSync(path.join(root, 'storage.rules'), 'utf8');
  
  var maxAttempts = 100;
  var baseWait = 120; // 2 minutos entre tentativas
  
  console.log('=== RETRY PERSISTENTE — Regras Completas ===');
  console.log('Firestore: ' + fullRules.length + ' bytes');
  console.log('Storage: ' + storageRules.length + ' bytes');
  console.log('Max tentativas: ' + maxAttempts + ' | Wait: ' + baseWait + 's');
  console.log('');
  
  // FASE 1: Firestore full rules
  var firestoreDeployed = false;
  for (var attempt = 1; attempt <= maxAttempts && !firestoreDeployed; attempt++) {
    var now = new Date().toISOString();
    console.log('[' + now + '] === Tentativa ' + attempt + '/' + maxAttempts + ' ===');
    
    firestoreDeployed = await tryDeployRules('firestore-full', fullRules, 'firestore.rules');
    
    if (!firestoreDeployed) {
      var wait = baseWait + Math.min(attempt * 10, 120);
      console.log('[wait] ' + wait + 's...');
      await sleep(wait * 1000);
    }
  }
  
  if (!firestoreDeployed) {
    console.log('Firestore rules: FALHOU apos ' + maxAttempts + ' tentativas');
    process.exit(1);
  }
  
  console.log('');
  console.log('Firestore rules OK! Aguardar 30s...');
  await sleep(30000);
  
  // FASE 2: Storage rules
  var storageDeployed = false;
  for (var attempt2 = 1; attempt2 <= 20 && !storageDeployed; attempt2++) {
    storageDeployed = await tryDeployRules('storage', storageRules, 'storage.rules');
    if (!storageDeployed) {
      await sleep(90000);
    }
  }
  
  // FASE 3: Firestore indexes
  console.log('');
  console.log('=== Firestore Indexes ===');
  try {
    var execSync = require('child_process').execSync;
    execSync('npx firebase deploy --only firestore:indexes --project gestaoyahweh-21e23 --non-interactive', {
      cwd: root, stdio: 'inherit', timeout: 120000,
    });
    console.log('[indexes] OK!');
  } catch (e) {
    console.log('[indexes] Falhou — tentar manual depois');
  }
  
  console.log('');
  console.log('TODAS AS REGRAS PUBLICADAS!');
}

main().catch(function(e) { console.error(e); process.exit(1); });
