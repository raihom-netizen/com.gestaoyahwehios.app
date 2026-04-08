/**
 * Grava credenciais de PRODUÇÃO do Mercado Pago em config/mercado_pago.
 * Uso: node scripts/seed-mercado-pago.js
 * Requer GOOGLE_APPLICATION_CREDENTIALS ou secrets/gestaoyahweh-*.json
 */

import admin from 'firebase-admin';
import path from 'path';
import fs from 'fs';

const CREDENCIAIS_PRODUCAO = {
  publicKey: 'APP_USR-619344a5-2fc9-4af6-8dbe-59a83c517859',
  accessToken: 'APP_USR-6126885849829706-021110-1063e221940638c7f899a2a626f3b461-270646278',
  clientId: '6126885849829706',
  clientSecret: 'sK6EhTN8KZKr4VXpewtcSODh1TPShyNs',
  mode: 'production',
};

async function run() {
  if (!admin.apps.length) {
    const baseDir = process.cwd();
    const keyPaths = [
      path.join(baseDir, '..', 'secrets', 'gestaoyahweh-21e23-7951f1817911.json'),
      path.join(baseDir, 'secrets', 'gestaoyahweh-21e23-7951f1817911.json'),
    ];
    for (const keyPath of keyPaths) {
      if (fs.existsSync(keyPath)) {
        process.env.GOOGLE_APPLICATION_CREDENTIALS = keyPath;
        break;
      }
    }
    admin.initializeApp({ projectId: 'gestaoyahweh-21e23' });
  }
  const db = admin.firestore();
  await db.collection('config').doc('mercado_pago').set({
    ...CREDENCIAIS_PRODUCAO,
    webhookUrl: '',
    publicKeyTest: '',
    accessTokenTest: '',
    clientIdTest: '',
    clientSecretTest: '',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('Credenciais Mercado Pago (produção) gravadas em config/mercado_pago.');
  console.log('Acesse o Painel Admin > Mercado Pago para editar.');
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
