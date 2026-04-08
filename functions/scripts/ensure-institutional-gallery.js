/**
 * Cria/atualiza documento Firestore e estrutura base no Storage para a galeria institucional do site.
 *
 * Uso (pasta functions):
 *   node scripts/ensure-institutional-gallery.js
 *
 * Credenciais: mesmo padrão dos outros scripts (ADC / GOOGLE_APPLICATION_CREDENTIALS).
 */
"use strict";

const admin = require("firebase-admin");

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "gestaoyahweh-21e23";
const defaultBucket =
  process.env.FIREBASE_STORAGE_BUCKET ||
  process.env.STORAGE_BUCKET ||
  "gestaoyahweh-21e23.firebasestorage.app";

if (!admin.apps.length) {
  admin.initializeApp({
    projectId,
    storageBucket: defaultBucket,
  });
}

const db = admin.firestore();
const bucket = admin.storage().bucket(defaultBucket);

async function main() {
  await db
    .doc("app_public/institutional_gallery")
    .set(
      {
        title: "Galeria Gestão YAHWEH",
        items: [],
        storageRoot: "public/gestao_yahweh",
        hint:
          "Preencha items[] com path/title/kind ou envie arquivos em public/gestao_yahweh/videos|fotos|pdf/",
        seededAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  console.log("Firestore OK: app_public/institutional_gallery");

  const markers = [
    [
      "public/gestao_yahweh/README.txt",
      "Gestão YAHWEH — mídia institucional.\nPastas: videos/ | fotos/ | pdf/\n",
    ],
    ["public/gestao_yahweh/videos/.keep", " "],
    ["public/gestao_yahweh/fotos/.keep", " "],
    ["public/gestao_yahweh/pdf/.keep", " "],
  ];

  for (const [path, text] of markers) {
    const f = bucket.file(path);
    const [exists] = await f.exists();
    if (exists) continue;
    await f.save(Buffer.from(text, "utf8"), {
      contentType: "text/plain; charset=utf-8",
      metadata: { cacheControl: "public, max-age=600" },
    });
    console.log("Storage OK:", path);
  }

  console.log("ensure-institutional-gallery: concluido.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
