#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const { getAccessToken } = require('./gcp_rules_auth.cjs');

(async () => {
  const root = path.join(__dirname, '..');
  const { token, source } = await getAccessToken({ preferAdc: false });
  console.log('auth', source);
  const pid = 'gestaoyahweh-21e23';
  const base = `https://firebaserules.googleapis.com/v1/projects/${pid}`;
  const content = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const r = await fetch(`${base}/rulesets`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ source: { files: [{ name: 'firestore.rules', content }] } }),
  });
  const text = await r.text();
  console.log('POST status', r.status);
  console.log(text.slice(0, 400));
  process.exit(r.ok ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
