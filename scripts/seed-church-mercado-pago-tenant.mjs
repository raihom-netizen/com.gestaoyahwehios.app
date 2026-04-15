/**
 * Grava credenciais Mercado Pago de UMA igreja em:
 *   igrejas/{tenantId}/private/mp_credentials
 *   igrejas/{tenantId}/config/mercado_pago
 *
 * Não commite segredos no repositório — use variáveis de ambiente ou rode uma vez na sua máquina.
 *
 * PowerShell (exemplo):
 *   $env:TENANT_ID="igreja_o_brasil_para_cristo_jardim_goiano"
 *   $env:MP_ACCESS_TOKEN="APP_USR-..."
 *   $env:MP_PUBLIC_KEY="APP_USR-..."
 *   $env:MP_CLIENT_ID="4492571597826679"
 *   $env:MP_CLIENT_SECRET="..."
 *   $env:MP_WEBHOOK_SECRET="..."   # opcional — assinatura do painel Webhooks MP
 *   node scripts/seed-church-mercado-pago-tenant.mjs
 */

import admin from 'firebase-admin';
import path from 'path';
import fs from 'fs';

const tenantId =
  process.env.TENANT_ID?.trim() ||
  'igreja_o_brasil_para_cristo_jardim_goiano';

function req(name) {
  const v = process.env[name]?.trim();
  if (!v) {
    throw new Error(`Defina a variável de ambiente ${name}`);
  }
  return v;
}

async function run() {
  if (!admin.apps.length) {
    const baseDir = process.cwd();
    const keyPaths = [
      path.join(baseDir, 'secrets', 'gestaoyahweh-21e23-7951f1817911.json'),
      path.join(baseDir, '..', 'secrets', 'gestaoyahweh-21e23-7951f1817911.json'),
    ];
    for (const keyPath of keyPaths) {
      if (fs.existsSync(keyPath)) {
        process.env.GOOGLE_APPLICATION_CREDENTIALS = keyPath;
        break;
      }
    }
    admin.initializeApp({ projectId: 'gestaoyahweh-21e23' });
  }

  const accessToken = req('MP_ACCESS_TOKEN');
  const publicKey = req('MP_PUBLIC_KEY');
  const clientId = req('MP_CLIENT_ID');
  const clientSecret = req('MP_CLIENT_SECRET');
  const webhookSecret = process.env.MP_WEBHOOK_SECRET?.trim() || '';

  const db = admin.firestore();
  const priv = {
    accessToken,
    publicKey,
    clientSecret,
    mode: 'production',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (webhookSecret) priv.webhookSecret = webhookSecret;

  await db
    .collection('igrejas')
    .doc(tenantId)
    .collection('private')
    .doc('mp_credentials')
    .set(priv, { merge: true });

  const cfg = {
    enabled: true,
    mode: 'production',
    publicKey,
    clientId,
    hasClientSecret: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (webhookSecret) cfg.hasWebhookSecret = true;

  await db
    .collection('igrejas')
    .doc(tenantId)
    .collection('config')
    .doc('mercado_pago')
    .set(cfg, { merge: true });

  console.log(`OK — Mercado Pago gravado para igreja: ${tenantId}`);
  console.log('Confira em Configurações do painel da igreja (campos públicos + flags de segredo).');
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
