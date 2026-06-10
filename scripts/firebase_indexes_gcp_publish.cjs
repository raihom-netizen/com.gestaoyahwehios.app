#!/usr/bin/env node
/**
 * Publica indices Firestore via firestore.googleapis.com (sem firebase deploy /test).
 * Compara firestore.indexes.json com indices remotos e cria apenas os em falta.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const repoRoot = path.join(__dirname, '..');
const args = process.argv.slice(2);
const force = args.includes('--force');
const maxArg = args.find((a) => a.startsWith('--max-attempts='));
const maxAttempts = maxArg ? parseInt(maxArg.split('=')[1], 10) : (force ? 25 : 12);
const projectId =
  args.find((a) => !a.startsWith('--')) ||
  process.env.GCLOUD_PROJECT ||
  'gestaoyahweh-21e23';

function sha256Hex(content) {
  return crypto.createHash('sha256').update(content, 'utf8').digest('hex');
}

function readIndexesJson() {
  const p = path.join(repoRoot, 'firestore.indexes.json');
  let raw = fs.readFileSync(p, 'utf8');
  if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);
  return JSON.parse(raw).indexes || [];
}

function findServiceAccountKey() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
    return process.env.GOOGLE_APPLICATION_CREDENTIALS;
  }
  for (const dir of [path.join(repoRoot, 'ANDROID'), path.join(repoRoot, 'secrets')]) {
    if (!fs.existsSync(dir)) continue;
    for (const name of fs.readdirSync(dir)) {
      if (name.includes('firebase-adminsdk') && name.endsWith('.json')) {
        return path.join(dir, name);
      }
    }
  }
  return null;
}

async function getAccessToken() {
  const keyPath = findServiceAccountKey();
  if (!keyPath) throw new Error('Conta de servico nao encontrada (ANDROID/*-firebase-adminsdk*.json)');
  const functionsDir = path.join(repoRoot, 'functions');
  if (!fs.existsSync(path.join(functionsDir, 'node_modules', 'google-auth-library'))) {
    throw new Error('Execute: cd functions && npm install');
  }
  process.chdir(functionsDir);
  const { GoogleAuth } = require('google-auth-library');
  const auth = new GoogleAuth({
    keyFile: keyPath,
    scopes: ['https://www.googleapis.com/auth/cloud-platform', 'https://www.googleapis.com/auth/datastore'],
  });
  const client = await auth.getClient();
  const res = await client.getAccessToken();
  const token = (res && res.token) ? res.token : String(res || '');
  if (token.length < 20) throw new Error('Token OAuth vazio');
  return token;
}

async function apiCall(method, url, token, body) {
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
    throw err;
  }
  return text ? JSON.parse(text) : {};
}

function isTransient(err) {
  const s = String(err.status || err.message || '');
  return s === '503' || s === '504' || s === '429' || /unavailable|timeout|ECONNRESET/i.test(String(err.message));
}

async function withRetry(label, fn) {
  let lastErr;
  for (let a = 1; a <= maxAttempts; a++) {
    try {
      return await fn(a);
    } catch (err) {
      lastErr = err;
      if (!isTransient(err) || a >= maxAttempts) break;
      const wait = Math.min(120, 6 * a + Math.floor(Math.random() * 10));
      process.stderr.write(`[${label}] transiente ${a}/${maxAttempts}, aguardar ${wait}s...\n`);
      await new Promise((r) => setTimeout(r, wait * 1000));
    }
  }
  throw lastErr;
}

function normalizeField(f) {
  const out = { fieldPath: f.fieldPath };
  if (f.order) out.order = f.order;
  if (f.arrayConfig) out.arrayConfig = f.arrayConfig;
  if (f.vectorConfig) out.vectorConfig = f.vectorConfig;
  return out;
}

function fieldsForKey(fields) {
  return (fields || [])
    .filter((f) => f.fieldPath && f.fieldPath !== '__name__')
    .map((f) => {
      if (f.order) return `${f.fieldPath}:${f.order}`;
      if (f.arrayConfig) return `${f.fieldPath}:ARRAY_${f.arrayConfig}`;
      if (f.vectorConfig) return `${f.fieldPath}:VECTOR`;
      return `${f.fieldPath}:?`;
    })
    .join('|');
}

function indexKey(ix) {
  return `${ix.collectionGroup}#${ix.queryScope || 'COLLECTION'}#${fieldsForKey(ix.fields)}`;
}

function remoteCollectionGroup(ix) {
  const m = String(ix.name || '').match(/collectionGroups\/([^/]+)\/indexes\//);
  if (m) return m[1];
  return ix.collectionGroup || '';
}

function remoteToKey(ix) {
  return `${remoteCollectionGroup(ix)}#${ix.queryScope || 'COLLECTION'}#${fieldsForKey(ix.fields)}`;
}

function isIndexCreateSkippable(err) {
  const msg = String(err.message || err).toLowerCase();
  return (
    err.status === 409 ||
    /already exists/i.test(msg) ||
    (err.status === 400 && /not necessary|single field index/i.test(msg))
  );
}

async function listRemoteIndexes(token) {
  const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/-/indexes`;
  const all = [];
  let pageToken = '';
  for (let page = 0; page < 20; page++) {
    const q = pageToken ? `?pageToken=${encodeURIComponent(pageToken)}` : '';
    const resp = await apiCall('GET', `${base}${q}`, token, null);
    for (const ix of resp.indexes || []) {
      all.push(ix);
    }
    pageToken = resp.nextPageToken || '';
    if (!pageToken) break;
  }
  return all;
}

async function createIndex(token, localIx) {
  const cg = localIx.collectionGroup;
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/${encodeURIComponent(cg)}/indexes`;
  const body = {
    queryScope: localIx.queryScope || 'COLLECTION',
    fields: (localIx.fields || []).map(normalizeField),
  };
  return apiCall('POST', url, token, body);
}

function writeDeployStateIndexes(results) {
  const stateDir = path.join(repoRoot, '.deploy-state');
  if (!fs.existsSync(stateDir)) fs.mkdirSync(stateDir, { recursive: true });
  const statePath = path.join(stateDir, 'firebase-sync.json');
  let state = {};
  if (fs.existsSync(statePath)) {
    try {
      state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    } catch (_) {}
  }
  const ixPath = path.join(repoRoot, 'firestore.indexes.json');
  state.syncedAt = new Date().toISOString();
  state.projectId = projectId;
  state.indexesSha256 = sha256Hex(fs.readFileSync(ixPath, 'utf8').replace(/^\uFEFF/, ''));
  state.indexesVia = 'firebase_indexes_gcp_publish.cjs';
  state.indexesResults = results;
  fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
}

async function main() {
  const local = readIndexesJson();
  let token = await getAccessToken();
  const remote = await withRetry('list', async (attempt) => {
    if (attempt > 1 && (attempt - 1) % 5 === 0) token = await getAccessToken();
    return listRemoteIndexes(token);
  });

  const remoteKeys = new Set(remote.map(remoteToKey));
  const missing = local.filter((ix) => !remoteKeys.has(indexKey(ix)));
  const results = {
    localCount: local.length,
    remoteCount: remote.length,
    missingCount: missing.length,
    created: [],
    alreadySynced: missing.length === 0,
  };

  if (missing.length === 0) {
    process.stdout.write(`OK indexes already_synced local=${local.length} remote=${remote.length}\n`);
    writeDeployStateIndexes(results);
    process.stdout.write(`YAHWEH_INDEXES_OK=${JSON.stringify({ ok: true, projectId, results })}\n`);
    process.exit(0);
  }

  process.stdout.write(`Criar ${missing.length} indice(s) em falta (local=${local.length}, remote=${remote.length})...\n`);
  for (const ix of missing) {
    const key = indexKey(ix);
    try {
      const op = await withRetry(key, async (attempt) => {
        if (attempt > 1 && (attempt - 1) % 4 === 0) token = await getAccessToken();
        return createIndex(token, ix);
      });
      results.created.push({ key, name: op.name || null, state: op.state || 'CREATING' });
      process.stdout.write(`OK created ${key}\n`);
    } catch (err) {
      if (isIndexCreateSkippable(err)) {
        const action = err.status === 400 ? 'single_field_auto' : 'already_exists';
        results.created.push({ key, action });
        process.stdout.write(`OK skip ${key} (${action})\n`);
        continue;
      }
      throw err;
    }
  }

  writeDeployStateIndexes(results);
  process.stdout.write(`YAHWEH_INDEXES_OK=${JSON.stringify({ ok: true, projectId, results })}\n`);
  process.exit(0);
}

main().catch((err) => {
  process.stderr.write(String(err.message || err) + '\n');
  process.stdout.write(`YAHWEH_INDEXES_OK=${JSON.stringify({ ok: false, error: String(err.message || err) })}\n`);
  process.exit(1);
});
