#!/usr/bin/env node
'use strict';
/** Publica firestore.rules com minimo de chamadas GCP (GET release -> POST ruleset -> PATCH release). */
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const { getAccessToken } = require('./gcp_rules_auth.cjs');

const projectId = process.argv[2] || 'gestaoyahweh-21e23';
const repoRoot = path.join(__dirname, '..');
const GAP_MS = Math.max(90000, parseInt(process.env.YAHWEH_RULES_MIN_GAP_SEC || '90', 10) * 1000);

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function fingerprintFor(content) {
  return crypto.createHash('sha256').update(content, 'utf8').digest('base64');
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

function isTransient(status) {
  return status === 429 || status === 503 || status === 504;
}

async function call(token, method, url, body, label) {
  let lastErr;
  for (let a = 1; a <= 15; a++) {
    const res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    if (res.ok) return text ? JSON.parse(text) : {};
    lastErr = new Error(`HTTP ${res.status}: ${text.slice(0, 350)}`);
    lastErr.status = res.status;
    if (!isTransient(res.status) || a >= 15) throw lastErr;
    const waitSec = Math.min(600, GAP_MS / 1000 + 20 * a);
    process.stderr.write(`[firestore-min] ${label} ${res.status} retry ${a}/15, aguardar ${waitSec}s...\n`);
    await sleep(waitSec * 1000);
    if (a % 4 === 0) token = (await getAccessToken({})).token;
  }
  throw lastErr;
}

async function main() {
  const initial = Math.max(GAP_MS * 2, parseInt(process.env.YAHWEH_RULES_INITIAL_WAIT_SEC || '180', 10) * 1000);
  process.stderr.write(`[firestore-min] cooldown ${initial / 1000}s...\n`);
  await sleep(initial);

  const content = fs.readFileSync(path.join(repoRoot, 'firestore.rules'), 'utf8');
  const localNorm = content.replace(/\r\n/g, '\n').trim();
  const fp = fingerprintFor(content);
  let { token } = await getAccessToken({});
  const base = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;
  const releaseName = 'cloud.firestore';
  const fullRelease = `projects/${projectId}/releases/${releaseName}`;

  process.stderr.write(`[firestore-min] GET release ${releaseName}...\n`);
  let remoteNorm = '';
  try {
    const rel = await call(token, 'GET', `${base}/releases/${encodeURIComponent(releaseName)}`, null, 'GET release');
    if (rel.rulesetName) {
      const rs = await call(
        token,
        'GET',
        `https://firebaserules.googleapis.com/v1/${rel.rulesetName}`,
        null,
        'GET ruleset atual'
      );
      for (const f of rs.source?.files || []) {
        if (String(f.name).endsWith('.rules')) {
          remoteNorm = decodeRulesFileContent(f.content).replace(/\r\n/g, '\n').trim();
          break;
        }
      }
    }
  } catch (e) {
    process.stderr.write(`[firestore-min] leitura remota: ${String(e.message || e).slice(0, 120)}\n`);
  }

  if (remoteNorm && remoteNorm === localNorm) {
    process.stdout.write(
      `YAHWEH_FIRESTORE_PATCH_OK=${JSON.stringify({ ok: true, action: 'already_synced', release: releaseName })}\n`
    );
    return;
  }

  process.stderr.write(`[firestore-min] aguardar ${GAP_MS / 1000}s antes de POST ruleset...\n`);
  await sleep(GAP_MS);
  const created = await call(
    token,
    'POST',
    `${base}/rulesets`,
    { source: { files: [{ name: 'firestore.rules', content, fingerprint: fp }] } },
    'POST ruleset'
  );
  const rulesetName = created.name;
  process.stderr.write(`[firestore-min] ruleset=${rulesetName}\n`);

  process.stderr.write(`[firestore-min] aguardar ${GAP_MS / 1000}s antes de PATCH release...\n`);
  await sleep(GAP_MS);
  await call(
    token,
    'PATCH',
    `${base}/releases/${encodeURIComponent(releaseName)}`,
    { release: { name: fullRelease, rulesetName } },
    'PATCH release'
  );

  const stateDir = path.join(repoRoot, '.deploy-state');
  if (!fs.existsSync(stateDir)) fs.mkdirSync(stateDir, { recursive: true });
  fs.writeFileSync(
    path.join(stateDir, 'firebase-sync.json'),
    JSON.stringify(
      {
        syncedAt: new Date().toISOString(),
        projectId,
        firestoreRulesSha256: crypto.createHash('sha256').update(content, 'utf8').digest('hex'),
        via: 'firestore_rules_patch_release.cjs',
      },
      null,
      2
    )
  );

  process.stdout.write(
    `YAHWEH_FIRESTORE_PATCH_OK=${JSON.stringify({ ok: true, action: 'published', rulesetName, release: releaseName })}\n`
  );
}

main().catch((err) => {
  process.stderr.write(String(err.message || err) + '\n');
  process.stdout.write(`YAHWEH_FIRESTORE_PATCH_OK=${JSON.stringify({ ok: false, error: String(err.message || err) })}\n`);
  process.exit(1);
});
