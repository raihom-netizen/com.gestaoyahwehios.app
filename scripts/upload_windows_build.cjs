'use strict';
/**
 * Sobe o ZIP do executável Windows para o Firebase Storage, torna público e
 * grava a URL em config/appDownloads.windowsUrl (o site de divulgação lê daí).
 *
 * Uso: node scripts/upload_windows_build.cjs <caminho-do-zip> [build]
 */
const path = require('path');
const fs = require('fs');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');

const zipPath = process.argv[2];
const build = process.argv[3] || '2181';
if (!zipPath || !fs.existsSync(zipPath)) {
  console.error('ZIP não encontrado:', zipPath);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(KEY)),
  storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
});

(async () => {
  const bucket = admin.storage().bucket();
  const dest = `downloads/windows/GestaoYahweh-Windows-${build}.zip`;
  console.log('Subindo', zipPath, '->', dest, `(${(fs.statSync(zipPath).size / 1048576).toFixed(1)} MB)`);

  await bucket.upload(zipPath, {
    destination: dest,
    resumable: true,
    metadata: {
      contentType: 'application/zip',
      cacheControl: 'public, max-age=300',
      metadata: { build: String(build), platform: 'windows' },
    },
  });

  const file = bucket.file(dest);
  await file.makePublic();
  const publicUrl = `https://storage.googleapis.com/${bucket.name}/${dest}`;
  console.log('Público:', publicUrl);

  const db = admin.firestore();
  await db.doc('config/appDownloads').set({
    windowsUrl: publicUrl,
    windowsBuild: String(build),
    windowsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  // Link de atualização DENTRO do app Windows (Configurações), igual Android/iOS.
  await db.doc('config/appVersion').set({
    storeUrlWindows: publicUrl,
  }, { merge: true });

  const after = (await db.doc('config/appDownloads').get()).data() || {};
  console.log('config/appDownloads.windowsUrl =', after.windowsUrl);
  console.log('config/appVersion.storeUrlWindows = (mesmo URL)');
  console.log('OK: Windows', build, 'publicado e linkado no site.');
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e); process.exit(1); });
