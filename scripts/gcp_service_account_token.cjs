// Emite access token OAuth2 a partir de JSON de conta de servico (sem gcloud).
// Uso: node scripts/gcp_service_account_token.cjs <caminho-chave.json>
'use strict';

const fs = require('fs');
const path = require('path');

const keyPath = process.argv[2];
if (!keyPath || !fs.existsSync(keyPath)) {
  process.exit(2);
}

const functionsDir = path.join(__dirname, '..', 'functions');
const gal = path.join(functionsDir, 'node_modules', 'google-auth-library');
if (!fs.existsSync(gal)) {
  process.stderr.write('google-auth-library em falta — execute npm install em functions/\n');
  process.exit(3);
}

process.chdir(functionsDir);

const { GoogleAuth } = require('google-auth-library');

(async () => {
  const auth = new GoogleAuth({
    keyFile: path.resolve(keyPath),
    scopes: [
      'https://www.googleapis.com/auth/cloud-platform',
      'https://www.googleapis.com/auth/firebase',
    ],
  });
  const client = await auth.getClient();
  const res = await client.getAccessToken();
  const token = (res && res.token) ? res.token : String(res || '');
  if (token.length < 20) process.exit(4);
  process.stdout.write(token);
})().catch((err) => {
  process.stderr.write(String(err && err.message ? err.message : err) + '\n');
  process.exit(1);
});
