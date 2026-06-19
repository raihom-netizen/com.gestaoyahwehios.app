#!/usr/bin/env node
/**
 * Publicacao permanente Firestore + Storage rules via Firebase Rules API (Google Cloud).
 * Nao usa firebase deploy /test (evita 503 no CLI).
 *
 * Uso:
 *   node scripts/firebase_rules_gcp_publish.cjs
 *   node scripts/firebase_rules_gcp_publish.cjs --force --max-attempts=40
 *   node scripts/firebase_rules_gcp_publish.cjs --only=firestore|storage|all
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { getAccessToken, findCredentialKeyFile, repoRoot } = require('./gcp_rules_auth.cjs');
const args = process.argv.slice(2);
const force = args.includes('--force');
const onlyArg = args.find((a) => a.startsWith('--only='));
const only = onlyArg ? onlyArg.split('=')[1] : 'all';
const maxArg = args.find((a) => a.startsWith('--max-attempts='));
const maxAttempts = maxArg ? parseInt(maxArg.split('=')[1], 10) : (force ? 40 : 12);
const preferAdc = args.includes('--prefer-adc') || String(process.env.YAHWEH_GCP_PREFER_ADC || '') === '1';
const forceRepublish =
  args.includes('--force-republish') || String(process.env.YAHWEH_FORCE_REPUBLISH || '') === '1';
/** --force / force-republish: ignora lookup só se --skip-ruleset-lookup; senão reutiliza ruleset existente (evita POST 503). */
const skipRulesetLookup = args.includes('--skip-ruleset-lookup') || (force && !forceRepublish);
const projectId =
  args.find((a) => !a.startsWith('--')) ||
  process.env.GCLOUD_PROJECT ||
  'gestaoyahweh-21e23';

/** Quota GCP: 1 pedido de gestao/min em firebaserules.googleapis.com */
const MANAGEMENT_MIN_GAP_MS = Math.max(
  65000,
  parseInt(process.env.YAHWEH_RULES_MIN_GAP_SEC || '70', 10) * 1000
);
let lastManagementCallAt = 0;

async function throttleManagement(label) {
  const elapsed = Date.now() - lastManagementCallAt;
  if (lastManagementCallAt > 0 && elapsed < MANAGEMENT_MIN_GAP_MS) {
    const waitSec = Math.ceil((MANAGEMENT_MIN_GAP_MS - elapsed) / 1000);
    process.stderr.write(`[quota] aguardar ${waitSec}s antes de ${label} (1 req/min firebaserules)\n`);
    await new Promise((r) => setTimeout(r, waitSec * 1000));
  }
  lastManagementCallAt = Date.now();
}

const rulesFiles = {
  firestore: { local: 'firestore.rules', release: 'cloud.firestore', fileName: 'firestore.rules' },
  storage: { local: 'storage.rules', release: null, fileName: 'storage.rules' },
};

function sha256Hex(content) {
  return crypto.createHash('sha256').update(content, 'utf8').digest('hex');
}

function fingerprintFor(content) {
  return crypto.createHash('sha256').update(content, 'utf8').digest('base64');
}

async function resolveAccessToken(attempt) {
  if (attempt > 1 && (attempt - 1) % 5 === 0) {
    process.stderr.write(`[auth] token OAuth renovado (tentativa ${attempt})\n`);
  }
  const auth = await getAccessToken({ preferAdc });
  process.stderr.write(`[auth] fonte=${auth.source}${auth.keyFile ? ` key=${path.basename(auth.keyFile)}` : ''}\n`);
  return auth.token;
}

function decodeRulesFileContent(raw) {
  if (raw == null) return '';
  const s = String(raw);
  if (!s.trim()) return '';
  try {
    const decoded = Buffer.from(s, 'base64').toString('utf8');
    if (decoded.includes('service ') || decoded.includes('rules_version')) return decoded;
  } catch (_) {}
  return s;
}

async function apiCall(method, url, token, body, attempt) {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`HTTP ${res.status}: ${text.slice(0, 600)}`);
    err.status = res.status;
    err.attempt = attempt;
    throw err;
  }
  return text ? JSON.parse(text) : {};
}

function isTransient(err) {
  const s = String(err.status || err.message || '');
  return s === '503' || s === '504' || s === '429' || /unavailable|timeout|ECONNRESET|RESOURCE_EXHAUSTED|RATE_LIMIT/i.test(String(err.message));
}

async function withRetry(label, fn) {
  let lastErr;
  for (let a = 1; a <= maxAttempts; a++) {
    try {
      return await fn(a);
    } catch (err) {
      lastErr = err;
      if (!isTransient(err) || a >= maxAttempts) break;
      const status = String(err.status || '');
      const wait = status === '429'
        ? Math.min(600, Math.max(90, MANAGEMENT_MIN_GAP_MS / 1000) + 15 * a)
        : status === '503' || status === '504'
          ? Math.min(600, 60 + 30 * a)
          : Math.min(600, 8 * a + Math.floor(Math.random() * 12));
      process.stderr.write(`[${label}] ${status || 'transiente'}/retry ${a}/${maxAttempts}, aguardar ${wait}s...\n`);
      await new Promise((r) => setTimeout(r, wait * 1000));
    }
  }
  throw lastErr;
}

function acquirePublishLock() {
  const lockDir = path.join(repoRoot, '.deploy-state');
  if (!fs.existsSync(lockDir)) fs.mkdirSync(lockDir, { recursive: true });
  const lockPath = path.join(lockDir, 'firebase-rules-publish.lock');
  if (fs.existsSync(lockPath)) {
    const ageMs = Date.now() - fs.statSync(lockPath).mtimeMs;
    if (ageMs < 45 * 60 * 1000) {
      throw new Error(`Publicacao rules ja em curso (lock ${Math.round(ageMs / 1000)}s). Aguarde ou apague ${lockPath}`);
    }
    fs.unlinkSync(lockPath);
  }
  fs.writeFileSync(lockPath, `${process.pid}\n${new Date().toISOString()}`, 'utf8');
  return lockPath;
}

function releasePublishLock(lockPath) {
  try {
    if (lockPath && fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
  } catch (_) {}
}

async function resolveStorageReleaseName(base, token) {
  const resp = await apiCall('GET', `${base}/releases?pageSize=100`, token, null, 1);
  for (const r of resp.releases || []) {
    const n = String(r.name || '');
    if (n.includes('firebase.storage')) {
      return n.replace(/^projects\/[^/]+\/releases\//, '');
    }
  }
  return `firebase.storage/${projectId}.firebasestorage.app`;
}

async function resolveFirestoreReleaseName(base, token) {
  const resp = await apiCall('GET', `${base}/releases?pageSize=100`, token, null, 1);
  for (const r of resp.releases || []) {
    const n = String(r.name || '');
    if (n.includes('cloud.firestore')) {
      return n.replace(/^projects\/[^/]+\/releases\//, '');
    }
  }
  return 'cloud.firestore';
}

async function getReleaseRulesContent(base, token, releaseName) {
  const rel = await apiCall('GET', `${base}/releases/${encodeURIComponent(releaseName)}`, token, null, 1);
  const rulesetName = rel.rulesetName;
  if (!rulesetName) return null;
  const rs = await apiCall('GET', `https://firebaserules.googleapis.com/v1/${rulesetName}`, token, null, 1);
  for (const f of rs.source?.files || []) {
    if (String(f.name).endsWith('.rules')) {
      return decodeRulesFileContent(f.content);
    }
  }
  return null;
}

async function findRulesetByFingerprint(base, token, fp) {
  let pageToken = '';
  for (let page = 0; page < 5; page++) {
    const q = pageToken ? `?pageSize=50&pageToken=${pageToken}` : '?pageSize=50';
    const list = await apiCall('GET', `${base}/rulesets${q}`, token, null, 1);
    for (const rs of list.rulesets || []) {
      const full = await apiCall('GET', `https://firebaserules.googleapis.com/v1/${rs.name}`, token, null, 1);
      for (const f of full.source?.files || []) {
        if (f.fingerprint === fp) return rs.name;
      }
    }
    pageToken = list.nextPageToken || '';
    if (!pageToken) break;
  }
  return null;
}

async function publishRulesTarget(base, token, targetKey) {
  const cfg = rulesFiles[targetKey];
  const localPath = path.join(repoRoot, cfg.local);
  if (!fs.existsSync(localPath)) throw new Error(`${cfg.local} em falta`);

  const content = fs.readFileSync(localPath, 'utf8');
  const fp = fingerprintFor(content);
  const releaseName =
    targetKey === 'storage'
      ? await resolveStorageReleaseName(base, token)
      : await resolveFirestoreReleaseName(base, token);

  process.stderr.write(`[${targetKey}] release=${releaseName}\n`);
  const remote = await getReleaseRulesContent(base, token, releaseName).catch((e) => {
    process.stderr.write(`[${targetKey}] read release: ${String(e.message || e).slice(0, 120)}\n`);
    return null;
  });
  const localNorm = content.replace(/\r\n/g, '\n').trim();
  const remoteNorm = remote ? remote.replace(/\r\n/g, '\n').trim() : '';
  if (!forceRepublish && localNorm === remoteNorm) {
    return { target: targetKey, release: releaseName, action: 'already_synced', ruleset: null };
  }
  if (forceRepublish && localNorm === remoteNorm) {
    process.stderr.write(`[${targetKey}] force-republish: conteudo igual — novo ruleset + patch release\n`);
  }

  let rulesetName = null;
  if (!skipRulesetLookup) {
    rulesetName = await findRulesetByFingerprint(base, token, fp).catch(() => null);
  }

  if (!rulesetName) {
    process.stderr.write(`[${targetKey}] criar ruleset...\n`);
    await throttleManagement(`POST rulesets (${targetKey})`);
    const created = await apiCall(
      'POST',
      `${base}/rulesets`,
      token,
      {
        source: {
          files: [{ name: cfg.fileName, content, fingerprint: fp }],
        },
      },
      1
    );
    rulesetName = created.name;
  }

  process.stderr.write(`[${targetKey}] patch release ruleset=${rulesetName}\n`);
  await throttleManagement(`PATCH release (${targetKey})`);
  const releaseUrl = `${base}/releases/${encodeURIComponent(releaseName)}`;
  const fullReleaseName = `projects/${projectId}/releases/${releaseName}`;
  const patchBodies = [
    { release: { name: fullReleaseName, rulesetName } },
    { name: fullReleaseName, rulesetName },
  ];
  let lastErr;
  for (const body of patchBodies) {
    try {
      await apiCall('PATCH', releaseUrl, token, body, 1);
      return { target: targetKey, release: releaseName, action: 'published', ruleset: rulesetName };
    } catch (e) {
      lastErr = e;
      if (e.status !== 400) throw e;
    }
  }
  throw lastErr;
}

function writeDeployState(results) {
  const stateDir = path.join(repoRoot, '.deploy-state');
  if (!fs.existsSync(stateDir)) fs.mkdirSync(stateDir, { recursive: true });
  const fr = path.join(repoRoot, 'firestore.rules');
  const sr = path.join(repoRoot, 'storage.rules');
  const ix = path.join(repoRoot, 'firestore.indexes.json');
  const state = {
    syncedAt: new Date().toISOString(),
    projectId,
    firestoreRulesSha256: fs.existsSync(fr) ? sha256Hex(fs.readFileSync(fr, 'utf8')) : null,
    storageRulesSha256: fs.existsSync(sr) ? sha256Hex(fs.readFileSync(sr, 'utf8')) : null,
    indexesSha256: fs.existsSync(ix) ? sha256Hex(fs.readFileSync(ix, 'utf8')) : null,
    via: 'firebase_rules_gcp_publish.cjs',
    results,
  };
  fs.writeFileSync(path.join(stateDir, 'firebase-sync.json'), JSON.stringify(state, null, 2));
  fs.writeFileSync(
    path.join(stateDir, 'firebase-rules-pending.json'),
    JSON.stringify({ pending: false, clearedAt: state.syncedAt }, null, 2)
  );
}

async function main() {
  const lockPath = acquirePublishLock();
  try {
  const keyHint = findCredentialKeyFile();
  if (keyHint) {
    process.stderr.write(`[auth] chave disponivel: ${path.basename(keyHint)}\n`);
  }
  const targets = only === 'all' ? ['firestore', 'storage'] : [only];
  let token = await resolveAccessToken(1);
  const base = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;
  const results = [];

  for (let i = 0; i < targets.length; i++) {
    const t = targets[i];
    if (i > 0) {
      process.stderr.write(`[quota] pausa entre alvos (${targets[i - 1]} -> ${t})...\n`);
      await throttleManagement(`alvo ${t}`);
    }
    try {
      const r = await withRetry(t, async (attempt) => {
        token = await resolveAccessToken(attempt);
        return publishRulesTarget(base, token, t);
      });
      results.push(r);
      process.stdout.write(
        `OK ${t} ${r.action} release=${r.release}${r.ruleset ? ` ruleset=${r.ruleset}` : ''}\n`
      );
    } catch (err) {
      results.push({ target: t, action: 'failed', error: String(err.message || err).slice(0, 200) });
      throw err;
    }
  }

  writeDeployState(results);
  process.stdout.write(
    `YAHWEH_GCP_OK=${JSON.stringify({ ok: true, projectId, results })}\n`
  );
  } finally {
    releasePublishLock(lockPath);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
  try {
    const lockPath = path.join(repoRoot, '.deploy-state', 'firebase-rules-publish.lock');
    if (fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
  } catch (_) {}
  const pendingPath = path.join(repoRoot, '.deploy-state', 'firebase-rules-pending.json');
  try {
    const dir = path.join(repoRoot, '.deploy-state');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      pendingPath,
      JSON.stringify({
        pending: true,
        lastError: String(err.message || err).slice(0, 500),
        at: new Date().toISOString(),
      }, null, 2)
    );
  } catch (_) {}
  process.stderr.write(String(err.message || err) + '\n');
  process.stdout.write(`YAHWEH_GCP_OK=${JSON.stringify({ ok: false, error: String(err.message || err) })}\n`);
  process.exit(1);
});
