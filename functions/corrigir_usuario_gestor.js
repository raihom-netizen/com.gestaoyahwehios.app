// Script para corrigir automaticamente o vínculo do usuário gestor no Firestore
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

function loadCredential() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return admin.credential.applicationDefault();
  }
  const secretsPath = path.resolve(__dirname, "..", "secrets", "gestaoyahweh-21e23-7951f1817911.json");
  if (fs.existsSync(secretsPath)) {
    const serviceAccount = require(secretsPath);
    return admin.credential.cert(serviceAccount);
  }
  return admin.credential.applicationDefault();
}

admin.initializeApp({
  credential: loadCredential(),
});

const db = admin.firestore();

const cpf = "94536368191";
const email = "raihom@gmail.com";
const tenantId = "brasilparacristo_sistema";

async function corrigirUsuario() {
  let atualizado = false;
  // Tenta encontrar por CPF
  let snap = await db.collection("usuarios").where("cpf", "==", cpf).get();
  if (!snap.empty) {
    for (const doc of snap.docs) {
      await doc.ref.update({
        igrejaId: tenantId,
        role: "GESTOR",
        nivel: "GESTOR"
      });
      console.log("Usuário atualizado por CPF:", doc.id);
      atualizado = true;
    }
  }
  // Se não achou por CPF, tenta por e-mail
  if (!atualizado) {
    snap = await db.collection("usuarios").where("email", "==", email).get();
    if (!snap.empty) {
      for (const doc of snap.docs) {
        await doc.ref.update({
          igrejaId: tenantId,
          role: "GESTOR",
          nivel: "GESTOR"
        });
        console.log("Usuário atualizado por e-mail:", doc.id);
        atualizado = true;
      }
    }
  }
  if (!atualizado) {
    console.log("Usuário não encontrado por CPF nem e-mail.");
  }
  process.exit(0);
}

corrigirUsuario();
