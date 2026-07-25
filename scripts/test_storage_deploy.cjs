'use strict';
const fs = require('fs');
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));
const projectId = 'gestaoyahweh-21e23';
const base = 'https://firebaserules.googleapis.com/v1/projects/' + projectId;
const root = path.join(__dirname, '..');

(async () => {
  const auth = await getAccessToken();
  const content = fs.readFileSync(path.join(root, 'firestore.rules.slim2'), 'utf8');
  console.log('Storage: ' + content.length + ' bytes');
  
  const res = await fetch(base + '/rulesets', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + auth.token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content }] } }),
  });
  
  console.log('Status: ' + res.status);
  const d = await res.json();
  
  if (res.ok) {
    const rulesetName = d.name;
    console.log('Ruleset: ' + rulesetName);
    
    const releaseName = 'cloud.firestore';
    const encodedRelease = encodeURIComponent(releaseName);
    const fullReleaseName = 'projects/' + projectId + '/releases/' + releaseName;
    
    const patchBodies = [
      { release: { name: fullReleaseName, rulesetName: rulesetName } },
      { name: fullReleaseName, rulesetName: rulesetName },
    ];
    
    for (const body of patchBodies) {
      const patchRes = await fetch(base + '/releases/' + encodedRelease + '?updateMask=rulesetName', {
        method: 'PATCH',
        headers: { Authorization: 'Bearer ' + auth.token, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      console.log('PATCH: ' + patchRes.status);
      if (patchRes.ok) {
        console.log('STORAGE RULES DEPLOYED!');
        return;
      }
    }
    console.log('PATCH failed');
  } else {
    console.log('Error: ' + JSON.stringify(d).substring(0, 300));
  }
})();
