'use strict';

/**
 * Auth unificada GCP — Gestao YAHWEH (regras Firebase / indices).
 * Prioridade ( --prefer-adc ou YAHWEH_GCP_PREFER_ADC=1 ):
 *   1) Application Default Credentials (gcloud auth application-default login — Owner)
 *   2) Chave JSON (raiz > secrets > ANDROID)
 * Padrao:
 *   1) GOOGLE_APPLICATION_CREDENTIALS / YAHWEH_GCP_KEY_FILE
 *   2) Chave JSON (raiz > secrets > ANDROID)
 *   3) ADC
 */
const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..');

function envTruthy(name) {
  const v = String(process.env[name] || '').trim().toLowerCase();
  return v === '1' || v === 'true' || v === 'yes';
}

function isServiceAccountJson(filePath) {
  try {
    const j = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return Boolean(j.private_key && j.client_email && j.project_id);
  } catch (_) {
    return false;
  }
}

function findCredentialKeyFile() {
  const explicit = [
    process.env.YAHWEH_GCP_KEY_FILE,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
  ].filter(Boolean);
  for (const p of explicit) {
    if (p && fs.existsSync(p) && isServiceAccountJson(p)) return path.resolve(p);
  }

  const dirs = [
    repoRoot,
    path.join(repoRoot, 'secrets'),
    path.join(repoRoot, 'ANDROID'),
  ];
  const patterns = [
    /^gestaoyahweh-gcp-deploy-key\.json$/i,
    /^gestaoyahweh.*firebase-adminsdk.*\.json$/i,
    /^gestaoyahweh-21e23.*\.json$/i,
  ];
  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    for (const name of fs.readdirSync(dir)) {
      if (!name.endsWith('.json')) continue;
      if (name.includes('google-services') || name.includes('client_secret')) continue;
      if (!patterns.some((re) => re.test(name))) continue;
      const full = path.join(dir, name);
      if (isServiceAccountJson(full)) return full;
    }
  }
  return null;
}

function ensureFunctionsDir() {
  const functionsDir = path.join(repoRoot, 'functions');
  const gal = path.join(functionsDir, 'node_modules', 'google-auth-library');
  if (!fs.existsSync(gal)) {
    throw new Error('Execute: .\\scripts\\ensure_functions_node_for_gcp.ps1');
  }
  return functionsDir;
}

async function getAccessToken(options = {}) {
  const preferAdc =
    options.preferAdc === true ||
    envTruthy('YAHWEH_GCP_PREFER_ADC') ||
    envTruthy('YAHWEH_GCP_PREFER_OWNER');

  const functionsDir = ensureFunctionsDir();
  process.chdir(functionsDir);
  const { GoogleAuth } = require('google-auth-library');
  const scopes = options.scopes || [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/firebase',
  ];

  const keyPath = findCredentialKeyFile();

  async function tokenFromAdc() {
    const auth = new GoogleAuth({ scopes });
    const client = await auth.getClient();
    const res = await client.getAccessToken();
    const token = (res && res.token) ? res.token : String(res || '');
    if (token.length < 20) throw new Error('Token ADC vazio');
    return { token, source: 'adc_owner' };
  }

  async function tokenFromKey(kp) {
    const auth = new GoogleAuth({ keyFile: kp, scopes });
    const client = await auth.getClient();
    const res = await client.getAccessToken();
    const token = (res && res.token) ? res.token : String(res || '');
    if (token.length < 20) throw new Error('Token SA vazio');
    return { token, source: 'service_account', keyFile: kp };
  }

  const order = preferAdc
    ? [tokenFromAdc, () => (keyPath ? tokenFromKey(keyPath) : Promise.reject(new Error('sem chave')))]
    : [() => (keyPath ? tokenFromKey(keyPath) : Promise.reject(new Error('sem chave'))), tokenFromAdc];

  let lastErr;
  for (const fn of order) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr || new Error('Nenhuma credencial GCP disponivel');
}

module.exports = {
  repoRoot,
  findCredentialKeyFile,
  getAccessToken,
  isServiceAccountJson,
};
