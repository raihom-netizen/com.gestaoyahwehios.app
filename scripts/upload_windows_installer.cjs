'use strict';
/**
 * Sobe o INSTALADOR ÚNICO (.exe, Inno Setup) do app Windows para o Firebase
 * Storage, torna público e grava a URL em:
 *   - config/appDownloads.windowsUrl  (botão do site de divulgação)
 *   - config/appVersion.storeUrlWindows (update dentro do app, em Configurações)
 *
 * Diferença para `upload_windows_build.cjs`: aquele publica um ZIP da pasta
 * Release (o utilizador tinha de extrair e achar o .exe). Este publica um
 * instalador único — baixa, executa, instala.
 *
 * Uso: node scripts/upload_windows_installer.cjs <caminho-do-exe> <build>
 */
const path = require('path');
const fs = require('fs');
const admin = require(
  path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'),
);

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(
    __dirname, '..', 'ANDROID',
    'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json',
  );

const exePath = process.argv[2];
const build = process.argv[3];
if (!exePath || !fs.existsSync(exePath)) {
  console.error('Instalador .exe não encontrado:', exePath);
  process.exit(1);
}
if (!build) {
  console.error('Informe o build. Ex.: node scripts/upload_windows_installer.cjs setup.exe 2210');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(KEY)),
  storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
});

(async () => {
  const bucket = admin.storage().bucket();
  const dest = `downloads/windows/GestaoYahweh-Setup-${build}.exe`;
  const mb = (fs.statSync(exePath).size / 1048576).toFixed(1);
  console.log('Subindo', exePath, '->', dest, `(${mb} MB)`);

  await bucket.upload(exePath, {
    destination: dest,
    resumable: true,
    metadata: {
      // Tipo correto para o browser tratar como download de executável.
      contentType: 'application/vnd.microsoft.portable-executable',
      cacheControl: 'public, max-age=300',
      metadata: { build: String(build), platform: 'windows', kind: 'installer' },
    },
  });

  const file = bucket.file(dest);
  await file.makePublic();
  const publicUrl = `https://storage.googleapis.com/${bucket.name}/${dest}`;
  console.log('Público:', publicUrl);

  // Mantém APENAS a versão atual em downloads/windows/ — apaga builds antigos
  // (instaladores e zips) para não acumular custo/confusão no Storage.
  const [antigos] = await bucket.getFiles({ prefix: 'downloads/windows/' });
  const paraApagar = antigos.filter((f) => f.name !== dest);
  if (paraApagar.length === 0) {
    console.log('Limpeza: nada antigo para remover.');
  } else {
    for (const f of paraApagar) {
      await f.delete().catch((e) => {
        console.warn('  falhou apagar', f.name, '-', e.message);
      });
      console.log('  removido:', f.name);
    }
    console.log(`Limpeza: ${paraApagar.length} ficheiro(s) antigo(s) removido(s).`);
  }

  const db = admin.firestore();
  await db.doc('config/appDownloads').set({
    windowsUrl: publicUrl,
    windowsBuild: String(build),
    windowsKind: 'installer',
    windowsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.doc('config/appVersion').set({
    storeUrlWindows: publicUrl,
  }, { merge: true });

  const after = (await db.doc('config/appDownloads').get()).data() || {};
  console.log('config/appDownloads.windowsUrl =', after.windowsUrl);
  console.log('config/appDownloads.windowsBuild =', after.windowsBuild);
  console.log('config/appVersion.storeUrlWindows = (mesma URL)');
  console.log('OK: instalador Windows', build, 'publicado e linkado no site.');
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e); process.exit(1); });
