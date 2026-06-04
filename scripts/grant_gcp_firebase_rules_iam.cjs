#!/usr/bin/env node
/**
 * Concede roles IAM a conta de servico Firebase (firebaserules + firebase.admin).
 * Requer credenciais com permissao resourcemanager.projects.setIamPolicy (Owner/Editor humano).
 * Uso: node scripts/grant_gcp_firebase_rules_iam.cjs
 */
'use strict';

const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..');
const projectId = 'gestaoyahweh-21e23';

function findServiceAccountEmail() {
  for (const dir of [path.join(repoRoot, 'ANDROID'), path.join(repoRoot, 'secrets')]) {
    if (!fs.existsSync(dir)) continue;
    for (const name of fs.readdirSync(dir)) {
      if (name.includes('firebase-adminsdk') && name.endsWith('.json')) {
        const j = JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8'));
        return j.client_email;
      }
    }
  }
  return null;
}

function loadFromFunctions(pkg) {
  const functionsDir = path.join(repoRoot, 'functions');
  const modPath = path.join(functionsDir, 'node_modules', pkg);
  if (!fs.existsSync(modPath)) {
    return null;
  }
  return require(modPath);
}

function ensureNodeModulesHint() {
  console.error(
    'googleapis ausente. Execute na raiz: .\\scripts\\ensure_functions_node_for_gcp.ps1',
  );
  console.error('  ou: cd functions && npm ci --omit=dev');
}

async function main() {
  const email = findServiceAccountEmail();
  if (!email) {
    console.error('SA nao encontrada');
    process.exit(2);
  }
  const functionsDir = path.join(repoRoot, 'functions');
  if (!fs.existsSync(path.join(functionsDir, 'node_modules', 'googleapis'))) {
    const { spawnSync } = require('child_process');
    console.log('A instalar npm ci em functions/ (googleapis)...');
    const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
    const lock = fs.existsSync(path.join(functionsDir, 'package-lock.json'));
    const r = spawnSync(npm, lock ? ['ci', '--omit=dev'] : ['install', '--omit=dev'], {
      cwd: functionsDir,
      stdio: 'inherit',
      shell: process.platform === 'win32',
    });
    if (r.status !== 0) {
      ensureNodeModulesHint();
      process.exit(1);
    }
  }
  process.chdir(functionsDir);
  const googleMod = loadFromFunctions('googleapis');
  const authMod = loadFromFunctions('google-auth-library');
  if (!googleMod || !authMod) {
    ensureNodeModulesHint();
    process.exit(1);
  }
  const { google } = googleMod;
  const { GoogleAuth } = authMod;
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const crm = google.cloudresourcemanager('v1');
  const proj = await crm.projects.get({ auth: client, projectId });
  const policy = proj.data.policy || { bindings: [] };
  const roles = [
    'roles/firebaserules.system',
    'roles/firebase.admin',
    'roles/datastore.indexAdmin',
  ];
  for (const role of roles) {
    let binding = policy.bindings.find((b) => b.role === role);
    const member = `serviceAccount:${email}`;
    if (!binding) {
      binding = { role, members: [member] };
      policy.bindings.push(binding);
    } else if (!binding.members.includes(member)) {
      binding.members.push(member);
    }
    console.log(`IAM OK: ${role} -> ${email}`);
  }
  await crm.projects.setIamPolicy({
    auth: client,
    resource: projectId,
    requestBody: { policy },
  });
  console.log('Politica IAM actualizada.');
}

main().catch((e) => {
  console.error(e.message || e);
  console.error('Use conta Owner no gcloud auth application-default login ou Console IAM manual.');
  process.exit(1);
});
