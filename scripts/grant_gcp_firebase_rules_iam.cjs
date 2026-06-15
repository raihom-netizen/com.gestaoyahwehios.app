#!/usr/bin/env node
/**
 * Concede roles IAM a conta de servico Firebase (firebaserules + firebase.admin).
 * Preferencia: ADC Owner (gcloud auth application-default login).
 * Uso: node scripts/grant_gcp_firebase_rules_iam.cjs [--prefer-adc]
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { findCredentialKeyFile, getAccessToken } = require('./gcp_rules_auth.cjs');

const repoRoot = path.join(__dirname, '..');
const projectId = 'gestaoyahweh-21e23';
const preferAdc = process.argv.includes('--prefer-adc') || String(process.env.YAHWEH_GCP_PREFER_ADC || '') === '1';

function findServiceAccountEmail() {
  const key = findCredentialKeyFile();
  if (!key) return null;
  try {
    return JSON.parse(fs.readFileSync(key, 'utf8')).client_email;
  } catch (_) {
    return null;
  }
}

function loadFromFunctions(pkg) {
  const functionsDir = path.join(repoRoot, 'functions');
  const modPath = path.join(functionsDir, 'node_modules', pkg);
  if (!fs.existsSync(modPath)) return null;
  return require(modPath);
}

function ensureNodeModulesHint() {
  console.error('googleapis ausente. Execute: .\\scripts\\ensure_functions_node_for_gcp.ps1');
}

async function main() {
  const email = findServiceAccountEmail();
  if (!email) {
    console.error('SA nao encontrada (raiz/secrets/ANDROID gestaoyahweh*.json)');
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

  let client;
  try {
    const authInfo = await getAccessToken({ preferAdc });
    console.log(`Auth IAM: ${authInfo.source}`);
    if (authInfo.keyFile) {
      const auth = new GoogleAuth({
        keyFile: authInfo.keyFile,
        scopes: ['https://www.googleapis.com/auth/cloud-platform'],
      });
      client = await auth.getClient();
    } else {
      const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
      client = await auth.getClient();
    }
  } catch (e) {
    console.error(e.message || e);
    process.exit(1);
  }

  const crm = google.cloudresourcemanager('v1');
  const proj = await crm.projects.get({ auth: client, projectId });
  const policy = proj.data.policy || { bindings: [] };
  const policyEtag = policy.etag;
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
    requestBody: { policy: { ...policy, etag: policyEtag } },
  });
  console.log('Politica IAM actualizada.');
}

main().catch((e) => {
  console.error(e.message || e);
  console.error('Use conta Owner: .\\scripts\\setup_google_cloud_automatico.ps1');
  console.error('  (gcloud auth login + gcloud auth application-default login)');
  process.exit(1);
});
