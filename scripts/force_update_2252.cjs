// Força atualização SEGURA para 11.2.305+2252.
// - Web: publishedBuild=2252 -> painel oferece diálogo MANUAL "Atualizar"
//   (webRefresh é legado; na web o reload é sempre via botão do diálogo, nunca
//   automático — ver version_service.dart:236,264).
// - Mobile: PRESERVA minBuildNumber atual (NÃO tranca quem ainda não tem 2252
//   nas lojas Play/App Store; o AAB/iOS ainda vão ser publicados/revisados).
//   Depois que as lojas tiverem 2252, sobe-se minBuildNumber pelo painel.
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');

admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();

const MARKETING = '11.2.305';
const BUILD = 2252;
const FULL = `${MARKETING}+${BUILD}`;

(async () => {
  const ref = db.doc('config/appVersion');
  const before = (await ref.get()).data() || {};
  console.log('ANTES:', JSON.stringify({
    minVersion: before.minVersion,
    minBuildNumber: before.minBuildNumber,
    latestVersion: before.latestVersion,
    forceUpdate: before.forceUpdate,
    webRefresh: before.webRefresh,
    publishedBuild: before.publishedBuild,
  }, null, 2));

  // Preserva minBuildNumber (mobile) — nunca sobe aqui (evita travar lojas).
  const keepMinBuild = (typeof before.minBuildNumber === 'number')
    ? before.minBuildNumber
    : (parseInt(before.minBuildNumber, 10) || 0);

  const payload = {
    minVersion: MARKETING,
    minBuildNumber: keepMinBuild,           // <- NÃO trava mobile
    latestVersion: FULL,
    publishedBuild: FULL,
    forceUpdate: true,                      // gate por minBuildNumber (preservado)
    webRefresh: true,                       // <- legado; web = diálogo manual
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await ref.set(payload, { merge: true });

  const after = (await ref.get()).data() || {};
  console.log('DEPOIS:', JSON.stringify({
    minVersion: after.minVersion,
    minBuildNumber: after.minBuildNumber,
    latestVersion: after.latestVersion,
    forceUpdate: after.forceUpdate,
    webRefresh: after.webRefresh,
    publishedBuild: after.publishedBuild,
  }, null, 2));
  console.log('OK: web para', FULL, '| minBuildNumber mobile preservado em', keepMinBuild);
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e); process.exit(1); });
