#!/usr/bin/env node
'use strict';
// Delega ao publicador GCP permanente (Firestore only).
const { spawnSync } = require('child_process');
const path = require('path');
const script = path.join(__dirname, 'firebase_rules_gcp_publish.cjs');
const projectId = process.argv[2] || 'gestaoyahweh-21e23';
const r = spawnSync(process.execPath, [script, projectId, '--only=firestore', '--force', '--max-attempts=40'], {
  stdio: 'inherit',
  cwd: path.join(__dirname, '..'),
});
process.exit(r.status ?? 1);
