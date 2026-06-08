/**
 * Materializa igrejas/{tenantId}/financeiro/ no bucket (comprovantes).
 * Uso: node functions/scripts/materialize-financeiro-folder.js [tenantId]
 */
const admin = require("firebase-admin");

const DEFAULT_TENANT = "igreja_o_brasil_para_cristo_jardim_goiano";

const MIN_PNG = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44,
  0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f,
  0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00,
  0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

async function main() {
  const tenantId = (process.argv[2] || DEFAULT_TENANT).trim();
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      storageBucket: "gestaoyahweh-21e23.firebasestorage.app",
    });
  }
  const path = `igrejas/${tenantId}/financeiro/_structure/placeholder.png`;
  const file = admin.storage().bucket().file(path);
  const [exists] = await file.exists();
  if (exists) {
    console.log("OK — pasta financeiro já existe:", path);
    return;
  }
  await file.save(MIN_PNG, { contentType: "image/png", resumable: false });
  console.log("Criado:", path);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
