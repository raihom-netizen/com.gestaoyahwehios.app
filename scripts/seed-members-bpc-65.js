/**
 * Garante 65 membros na Igreja Brasil para Cristo (tenant: brasilparacristo_sistema).
 * Se já houver 65 ou mais, não altera. Caso contrário, adiciona membros de exemplo até completar 65.
 *
 * Uso: node seed-members-bpc-65.js
 * Requer GOOGLE_APPLICATION_CREDENTIALS ou secrets/gestaoyahweh-*.json
 */

import admin from 'firebase-admin';
import path from 'path';
import fs from 'fs';

const TENANT_ID = 'brasilparacristo_sistema';
const TARGET_COUNT = 65;

const NOMES_M = [
  'João Silva', 'Pedro Santos', 'Carlos Oliveira', 'José Pereira', 'Antônio Costa',
  'Francisco Lima', 'Paulo Souza', 'Marcos Almeida', 'Lucas Rodrigues', 'Gabriel Mendes',
  'Rafael Ferreira', 'Daniel Barbosa', 'Bruno Carvalho', 'Eduardo Rocha', 'Felipe Nascimento',
  'Gustavo Martins', 'Henrique Dias', 'Igor Freitas', 'Leandro Araújo', 'Mateus Correia',
  'Nathan Lopes', 'Ricardo Gomes', 'Thiago Moreira', 'Vinícius Reis', 'André Cardoso',
];
const NOMES_F = [
  'Maria Silva', 'Ana Santos', 'Juliana Oliveira', 'Fernanda Pereira', 'Camila Costa',
  'Patricia Lima', 'Adriana Souza', 'Marcia Almeida', 'Renata Rodrigues', 'Beatriz Mendes',
  'Carla Ferreira', 'Débora Barbosa', 'Eliane Carvalho', 'Helena Rocha', 'Isabela Nascimento',
  'Larissa Martins', 'Mariana Dias', 'Natália Freitas', 'Roberta Araújo', 'Sandra Correia',
  'Tatiana Lopes', 'Vanessa Gomes', 'Amanda Moreira', 'Bruna Reis', 'Cláudia Cardoso',
];

function randomBetween(a, b) {
  return Math.floor(Math.random() * (b - a + 1)) + a;
}

function generateMembers(howMany) {
  const members = [];
  let mi = 0, fi = 0;
  for (let i = 0; i < howMany; i++) {
    const isM = i % 2 === 0 || mi < fi;
    const nome = isM ? NOMES_M[mi++ % NOMES_M.length] : NOMES_F[fi++ % NOMES_F.length];
    const sexo = isM ? 'M' : 'F';
    const ano = randomBetween(1950, 2015);
    const mes = randomBetween(1, 12);
    const dia = randomBetween(1, 28);
    const dataNasc = new Date(ano, mes - 1, dia);
    members.push({
      NOME_COMPLETO: nome,
      SEXO: sexo,
      sexo: sexo.toLowerCase(),
      DATA_NASCIMENTO: admin.firestore.Timestamp.fromDate(dataNasc),
      STATUS: 'ativo',
      status: 'ativo',
      CRIADO_EM: admin.firestore.Timestamp.fromDate(new Date(2020 + randomBetween(0, 4), randomBetween(0, 11), randomBetween(1, 28))),
      SEED_BPC_65: true,
    });
  }
  return members;
}

async function run() {
  if (!admin.apps.length) {
    const keyPath = path.join(process.cwd(), '..', 'secrets', 'gestaoyahweh-21e23-7951f1817911.json');
    if (fs.existsSync(keyPath)) process.env.GOOGLE_APPLICATION_CREDENTIALS = keyPath;
    admin.initializeApp({ projectId: 'gestaoyahweh-21e23' });
  }
  const db = admin.firestore();
  const col = db.collection('tenants').doc(TENANT_ID).collection('members');

  const snap = await col.get();
  const current = snap.size;
  console.log(`Igreja Brasil para Cristo (${TENANT_ID}): ${current} membros.`);

  if (current >= TARGET_COUNT) {
    console.log(`Já possui ${current} membros. Nenhuma alteração.`);
    return;
  }

  const toAdd = TARGET_COUNT - current;
  const members = generateMembers(toAdd);
  let batch = db.batch();
  let count = 0;

  for (let i = 0; i < members.length; i++) {
    const id = `seed_bpc_${Date.now()}_${i}`;
    batch.set(col.doc(id), members[i], { merge: true });
    count++;
    if (count >= 450) {
      await batch.commit();
      batch = db.batch();
      count = 0;
    }
  }
  if (count > 0) await batch.commit();

  console.log(`Adicionados ${toAdd} membros. Total agora: ${current + toAdd}.`);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
