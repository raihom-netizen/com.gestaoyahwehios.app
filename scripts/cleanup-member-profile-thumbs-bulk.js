/**
 * Apaga no Storage objetos gerados por extensões (ex.: Resize Images) nas pastas
 * igrejas/{tenant}/membros/{id}/ — nomes thumb_*, foto_perfil_thumb/card/full, *_thumb.*, resized_*.
 * Mantém foto_perfil.jpg | .jpeg | .png.
 *
 * Requer credenciais de admin (mesmo padrão dos outros scripts):
 *   GOOGLE_APPLICATION_CREDENTIALS=... ou `gcloud auth application-default login`
 *
 * Uso (pasta scripts, após npm install):
 *   node cleanup-member-profile-thumbs-bulk.js
 *
 * Simular sem apagar:
 *   set DRY_RUN=1   (PowerShell: $env:DRY_RUN='1')
 *   node cleanup-member-profile-thumbs-bulk.js
 */

import admin from 'firebase-admin';

const PROJECT_ID = 'gestaoyahweh-21e23';
const STORAGE_BUCKET = 'gestaoyahweh-21e23.firebasestorage.app';
const DRY_RUN = process.env.DRY_RUN === '1' || process.env.DRY_RUN === 'true';

function isCanonicalMain(name) {
  const n = name.toLowerCase();
  return n === 'foto_perfil.jpg' || n === 'foto_perfil.jpeg' || n === 'foto_perfil.png';
}

function shouldDeleteGenerated(name) {
  const n = name.toLowerCase();
  if (isCanonicalMain(n)) return false;
  if (n.startsWith('thumb_')) return true;
  if (
    n.includes('foto_perfil_thumb') ||
    n.includes('foto_perfil_card') ||
    n.includes('foto_perfil_full')
  ) {
    return true;
  }
  if (n.includes('_thumb.') || n.includes('_card.') || n.includes('_full.')) return true;
  if (n.includes('resized_')) return true;
  return false;
}

/** @param {string} objectPath */
function isMemberProfileFile(objectPath) {
  return /^igrejas\/[^/]+\/membros\/[^/]+\/[^/]+$/.test(objectPath);
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: PROJECT_ID,
      storageBucket: STORAGE_BUCKET,
    });
  }
  const bucket = admin.storage().bucket(STORAGE_BUCKET);

  const toDelete = [];

  console.log(
    DRY_RUN
      ? '[DRY_RUN] Nenhum ficheiro será apagado.'
      : 'A apagar ficheiros gerados (thumbs) em igrejas/*/membros/* …',
  );

  await new Promise((resolve, reject) => {
    bucket
      .getFilesStream({ prefix: 'igrejas/' })
      .on('error', reject)
      .on('data', (file) => {
        const name = file.name;
        if (!isMemberProfileFile(name)) return;
        const base = name.split('/').pop() ?? '';
        if (!shouldDeleteGenerated(base)) return;
        toDelete.push(file);
      })
      .on('end', resolve);
  });

  let deleted = 0;
  for (const file of toDelete) {
    if (DRY_RUN) {
      console.log(`[dry-run] would delete: ${file.name}`);
      deleted++;
      continue;
    }
    try {
      await file.delete();
      deleted++;
      if (deleted % 50 === 0) console.log(`… ${deleted} apagados`);
    } catch (e) {
      console.error(`Falha ${file.name}:`, e.message || e);
    }
  }

  console.log(`Concluído. Objetos ${DRY_RUN ? 'identificados' : 'apagados'}: ${deleted}.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
