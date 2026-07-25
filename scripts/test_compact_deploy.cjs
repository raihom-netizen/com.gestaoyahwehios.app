/**
 * Deploy compact rules para testar o API — depois a completa
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));

const projectId = 'gestaoyahweh-21e23';
const base = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;
const root = path.join(__dirname, '..');

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
  const auth = await getAccessToken();
  const token = auth.token;
  
  // ===== COMPACT (75KB) =====
  const compactFile = path.join(root, 'firestore.rules.slim');
  const compact = fs.readFileSync(compactFile, 'utf8');
  console.log(`[compact] ${compact.length} bytes — tentar criar ruleset...`);
  
  const res = await fetch(base + '/rulesets', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      source: { files: [{ name: 'firestore.rules', content: compact }] },
    }),
  });
  
  console.log(`[compact] Status: ${res.status}`);
  const data = await res.json();
  
  if (res.ok) {
    const rulesetName = data.name;
    console.log(`[compact] ✓ Ruleset criado: ${rulesetName}`);
    
    // Patch release
    const encodedRelease = encodeURIComponent('cloud.firestore');
    const fullReleaseName = `projects/${projectId}/releases/cloud.firestore`;
    
    console.log(`[compact] Publicar release...`);
    const patchBodies = [
      { release: { name: fullReleaseName, rulesetName } },
      { name: fullReleaseName, rulesetName },
    ];
    
    for (const body of patchBodies) {
      const patchRes = await fetch(`${base}/releases/${encodedRelease}?updateMask=rulesetName`, {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
      
      console.log(`[compact] PATCH status: ${patchRes.status}`);
      if (patchRes.ok) {
        console.log(`[compact] ✓ REGRAS COMPACT PUBLICADAS!`);
        break;
      }
      const patchData = await patchRes.json();
      console.log(`[compact] PATCH error: ${JSON.stringify(patchData).substring(0, 300)}`);
    }
  } else {
    console.log(`[compact] Erro: ${JSON.stringify(data).substring(0, 500)}`);
    
    if (res.status === 503) {
      // Tentar a versão full também para comparar
      console.log('\n[full] 503 na compact — tentar full para confirmar...');
      const fullFile = path.join(root, 'firestore.rules');
      const full = fs.readFileSync(fullFile, 'utf8');
      console.log(`[full] ${full.length} bytes...`);
      
      const res2 = await fetch(base + '/rulesets', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          source: { files: [{ name: 'firestore.rules', content: full }] },
        }),
      });
      console.log(`[full] Status: ${res2.status}`);
      const data2 = await res2.json();
      console.log(`[full] Result: ${JSON.stringify(data2).substring(0, 300)}`);
    }
  }
}

main().catch(e => { console.error(e.message); process.exit(1); });
