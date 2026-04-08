const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { google } = require("googleapis");

async function getDrive() {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/drive"],
  });
  return google.drive({ version: "v3", auth });
}

async function uploadFile(drive, folderId, filePath) {
  const name = path.basename(filePath);
  const res = await drive.files.create({
    requestBody: {
      name,
      parents: [folderId],
    },
    media: {
      body: fs.createReadStream(filePath),
    },
    fields: "id, name",
  });
  return res.data;
}

async function main() {
  const files = process.argv.slice(2).filter(Boolean);
  if (!files.length) {
    throw new Error("Nenhum arquivo informado para upload.");
  }

  admin.initializeApp();
  const db = admin.firestore();

  const cfgSnap = await db.doc("config/appDownloads").get();
  const cfg = cfgSnap.data() || {};
  const folderId = String(cfg.driveFolderId || "").trim();

  if (!folderId) {
    throw new Error("config/appDownloads.driveFolderId ausente.");
  }

  const drive = await getDrive();
  for (const f of files) {
    if (!fs.existsSync(f)) {
      throw new Error(`Arquivo nao encontrado: ${f}`);
    }
    const info = await uploadFile(drive, folderId, f);
    console.log(`Uploaded: ${info.name} (${info.id})`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
