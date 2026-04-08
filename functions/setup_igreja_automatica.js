// Script para garantir usuário gestor e criar estrutura básica de tabelas para uma igreja
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


// Recebe parâmetros via linha de comando
const [,, igrejaId, igrejaNome, gestorEmail, gestorCpf, gestorNome, userId] = process.argv;
if (!igrejaId || !igrejaNome || !gestorEmail || !gestorCpf || !gestorNome || !userId) {
  console.error('Uso: node setup_igreja_automatica.js <igrejaId> <igrejaNome> <gestorEmail> <gestorCpf> <gestorNome> <userId>');
  process.exit(1);
}

const igrejaData = {
  ativa: true,
  email: gestorEmail,
  emailGestor: gestorEmail,
  gestorEmail: gestorEmail,
  name: igrejaNome,
  nome: igrejaNome,
  slug: igrejaId,
  updatedAt: new Date(),
};
const userData = {
  active: true,
  ativo: true,
  cpf: gestorCpf,
  email: gestorEmail,
  igrejaId: igrejaId,
  mustChangePass: false,
  name: gestorNome,
  role: "GESTOR",
  tenantId: igrejaId,
  uid: userId,
  updatedAt: new Date(),
};

async function criarEstruturaBasica() {
  // Cria documento da igreja
  await db.collection("igrejas").doc(igrejaId).set(igrejaData, { merge: true });
  // Cria usuário gestor
  await db.collection("users").doc(userId).set(userData, { merge: true });

  // Estruturas básicas para a igreja
  const colecoes = [
    "abastecimentos",
    "combustiveis",
    "veiculos",
    "usuarios",
    "relatorios",
    "members",
    "noticias",
    "fleet_vehicles",
    "fleet_fuelings",
    "fleet_documents",
    "frota_manutencao",
    "frota_abastecimentos",
    "frota_motoristas",
    "frota_veiculos",
    "frota_combustiveis",
    "frota_licenses"
  ];
  for (const col of colecoes) {
    // Cria um documento inicial para cada coleção (se não existir)
    const ref = db.collection(col).doc("_init_" + igrejaId);
    const snap = await ref.get();
    if (!snap.exists) {
      await ref.set({ igrejaId, createdAt: new Date(), init: true });
    }
  }
  console.log("Estrutura básica criada para a igreja e usuário gestor garantido.");
  process.exit(0);
}

criarEstruturaBasica();
