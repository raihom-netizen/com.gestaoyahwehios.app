'use strict';
/**
 * Lê (e opcionalmente define com --apply) o CORS do bucket do Firebase Storage.
 * Sem --apply: só imprime o CORS atual. Com --apply: publica CORS liberando
 * GET/HEAD (necessário p/ <video>/<img> no web) para os domínios oficiais.
 */
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));
const bucket = 'gestaoyahweh-21e23.firebasestorage.app';
const apiBase = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}`;

const desiredCors = [
  {
    origin: [
      'https://gestaoyahweh.com.br',
      'https://www.gestaoyahweh.com.br',
      'https://gestaoyahweh-21e23.web.app',
      'https://gestaoyahweh-21e23.firebaseapp.com',
      'http://localhost',
    ],
    method: ['GET', 'HEAD'],
    responseHeader: [
      'Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges',
      'Range', 'ETag', 'Cache-Control', 'Content-Disposition',
    ],
    maxAgeSeconds: 3600,
  },
];

async function main() {
  const apply = process.argv.includes('--apply');
  const { token } = await getAccessToken();
  const H = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

  const getRes = await fetch(`${apiBase}?fields=cors`, { headers: H });
  const getText = await getRes.text();
  console.log(`GET bucket cors -> ${getRes.status}`);
  console.log('CORS atual:', getText);

  if (!apply) {
    console.log('\n(somente leitura — rode com --apply para publicar o CORS de vídeo/imagem)');
    return;
  }

  const patchRes = await fetch(apiBase, {
    method: 'PATCH', headers: H,
    body: JSON.stringify({ cors: desiredCors }),
  });
  const patchText = await patchRes.text();
  console.log(`\nPATCH bucket cors -> ${patchRes.status}`);
  if (patchRes.ok) {
    console.log('✅ CORS aplicado. Vídeo/imagem no web liberado para os domínios oficiais.');
  } else {
    console.log('FALHOU:', patchText.substring(0, 600));
  }
}
main().catch((e) => { console.error('fatal:', e.message); process.exit(1); });
