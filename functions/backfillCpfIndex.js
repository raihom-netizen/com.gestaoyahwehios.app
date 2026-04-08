const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

(async () => {
  const cpf = "94536368191"; // TROQUE se quiser
  await db.doc(`publicCpfIndex/${cpf}`).set({
    cpf,
    name: "Igreja Teste",
    slug: "igreja-teste",
    churchId: "TESTE",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log("OK: publicCpfIndex criado para", cpf);
  process.exit(0);
})().catch((e) => {
  console.error("ERRO:", e);
  process.exit(1);
});
