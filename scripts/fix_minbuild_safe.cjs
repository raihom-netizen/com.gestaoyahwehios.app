const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
const KEY = path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');
admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
(async () => {
  const ref = admin.firestore().doc('config/appVersion');
  const d = (await ref.get()).data() || {};
  console.log('ATUAL: minBuildNumber =', d.minBuildNumber, '| publishedBuild =', d.publishedBuild, '| forceUpdate =', d.forceUpdate);
  if (typeof d.minBuildNumber === 'number' && d.minBuildNumber > 2153) {
    await ref.set({ minBuildNumber: 2153 }, { merge: true });
    console.log('CORRIGIDO: minBuildNumber -> 2153 (nao trava mobile das lojas em 2184).');
  } else {
    console.log('OK: minBuildNumber ja seguro (<=2153).');
  }
  process.exit(0);
})().catch(e => { console.error('ERRO:', e.message); process.exit(1); });
