#!/usr/bin/env node
/**
 * Upload do .ipa para Firebase Storage (public/...) + merge em Firestore app_public/ios_build
 * (link para divulgação / site). Requer FIREBASE_SERVICE_ACCOUNT_JSON e dependências em functions/.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = process.env.CM_BUILD_DIR || process.env.FCI_BUILD_DIR || process.cwd();
const ipaPath = process.argv[2];
const saJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

if (!saJson || !String(saJson).trim()) {
  console.log('FIREBASE_SERVICE_ACCOUNT_JSON vazio — a saltar upload IPA (Storage/Firestore).');
  process.exit(0);
}
if (!ipaPath || !fs.existsSync(ipaPath)) {
  console.error('IPA inválido ou ausente:', ipaPath);
  process.exit(0);
}

const fpRoot =
  fs.existsSync(path.join(root, 'flutter_app', 'pubspec.yaml')) ?
    path.join(root, 'flutter_app') :
    root;

process.chdir(path.join(root, 'functions'));
// eslint-disable-next-line import/no-dynamic-require
const admin = require('firebase-admin');

let cred;
try {
  cred = JSON.parse(saJson);
} catch (e) {
  console.error('FIREBASE_SERVICE_ACCOUNT_JSON não é JSON válido.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(cred),
  storageBucket: 'gestaoyahweh-21e23.appspot.com',
});

function readAppVersion() {
  const av = fs.readFileSync(path.join(fpRoot, 'lib', 'app_version.dart'), 'utf8');
  const m = av.match(/appVersion\s*=\s*'([^']+)'/);
  return m ? m[1] : null;
}

function readPubspecVersion() {
  const pub = fs.readFileSync(path.join(fpRoot, 'pubspec.yaml'), 'utf8');
  const m = pub.match(/^version:\s*([\d.]+)\+(\d+)/m);
  return m ? { base: m[1], build: m[2] } : { base: '0.0.0', build: '0' };
}

async function main() {
  const appVersion = readAppVersion();
  const pub = readPubspecVersion();
  const version = appVersion || pub.base;
  const buildNum = pub.build;

  const safeV = version.replace(/[^0-9.]/g, '_');
  const dest = `public/gestao_yahweh/builds/ios/GestaoYahweh_${safeV}_b${buildNum}.ipa`;

  const bucket = admin.storage().bucket();
  await bucket.upload(ipaPath, {
    destination: dest,
    metadata: {
      contentType: 'application/octet-stream',
      cacheControl: 'public, max-age=120',
    },
  });

  const file = bucket.file(dest);
  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: new Date(Date.now() + 1000 * 60 * 60 * 24 * 365 * 8),
  });

  await admin.firestore().doc('app_public/ios_build').set(
    {
      ipaDownloadUrl: url,
      ipaStoragePath: dest,
      version,
      buildNumber: parseInt(buildNum, 10) || 0,
      fileName: path.basename(dest),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log('OK: Storage + Firestore app_public/ios_build');
  console.log('   ', dest);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
