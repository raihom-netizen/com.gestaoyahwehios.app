'use strict';
/**
 * Sobe o INSTALADOR ÚNICO (.exe, Inno Setup) do Windows para o Firebase
 * Storage, torna público e grava a URL em:
 *   - config/appDownloads.windowsUrl   -> botão de download no site
 *   - config/appVersion.storeUrlWindows -> "Atualizar" dentro do app
 *
 * Diferença para upload_windows_exe_2200.cjs: aquele marcava contentType
 * 'application/zip' num arquivo .exe, o que faz alguns navegadores baixarem
 * com nome/handling errado. Aqui vai o tipo correto de executável Windows.
 *
 * Uso: node scripts/upload_windows_setup.cjs <caminho-do-setup.exe> <build>
 */
const path = require('path');
const fs = require('fs');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');

const setupPath = process.argv[2];
const build = process.argv[3];
if (!setupPath || !fs.existsSync(setupPath)) {
  console.error('Instalador nao encontrado:', setupPath);
  process.exit(1);
}
if (!build) {
  console.error('Informe o numero do build. Ex.: node scripts/upload_windows_setup.cjs dist/windows/Setup.exe 2211');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(KEY)),
  storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
});

(async () => {
  const bucket = admin.storage().bucket();
  const dest = `downloads/windows/GestaoYahweh-Setup-${build}.exe`;
  const sizeMb = (fs.statSync(setupPath).size / 1048576).toFixed(1);
  console.log('Subindo', setupPath, '->', dest, `(${sizeMb} MB)`);

  await bucket.upload(setupPath, {
    destination: dest,
    resumable: true,
    metadata: {
      contentType: 'application/vnd.microsoft.portable-executable',
      contentDisposition: `attachment; filename="GestaoYahweh-Setup-${build}.exe"`,
      cacheControl: 'public, max-age=300',
      metadata: { build: String(build), platform: 'windows', kind: 'installer' },
    },
  });

  const file = bucket.file(dest);
  await file.makePublic();
  const publicUrl = `https://storage.googleapis.com/${bucket.name}/${dest}`;
  console.log('Publico:', publicUrl);

  const db = admin.firestore();
  await db.doc('config/appDownloads').set({
    windowsUrl: publicUrl,
    windowsBuild: String(build),
    windowsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.doc('config/appVersion').set({
    storeUrlWindows: publicUrl,
  }, { merge: true });

  const after = (await db.doc('config/appDownloads').get()).data() || {};
  console.log('config/appDownloads.windowsUrl =', after.windowsUrl);
  console.log('config/appDownloads.windowsBuild =', after.windowsBuild);
  console.log('OK: instalador Windows', build, 'publicado e linkado no site.');
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e); process.exit(1); });
