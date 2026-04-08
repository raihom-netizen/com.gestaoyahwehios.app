/**
 * Importa CSV de membros (PLANILHA_SISTEMA_IGREJA_BPC_DB_V3 - MEMBERS.csv)
 * para a igreja Brasil para Cristo (tenant: brasilparacristo_sistema).
 *
 * - Com CPF válido (11 dígitos): importa como ativo, doc id = CPF; cria login (Auth + índices)
 *   com senha provisória 123456, exceto CPF 94536368191 (não altera senha).
 * - Sem CPF: importa como pendente para atualização depois.
 * - Ao entrar no app, o membro é direcionado a completar o cadastro.
 *
 * Uso (na pasta scripts):
 *   npm install
 *   node import-members-bpc.js "C:\Users\FAMILIA\Downloads\PLANILHA_SISTEMA_IGREJA_BPC_DB_V3 - MEMBERS.csv"
 *
 * Ou definir GOOGLE_APPLICATION_CREDENTIALS apontando para a chave do projeto Firebase.
 */

import fs from 'fs';
import path from 'path';
import { parse } from 'csv-parse';
import admin from 'firebase-admin';

const TENANT_ID = 'brasilparacristo_sistema';
const SENHA_PROVISORIA = '123456';
const CPF_MASTER = '94536368191'; // não definir senha; já tem login
const BATCH_SIZE = 450;
const MEMBRO_EMAIL_DOMAIN = 'membro.gestaoyahweh.com.br';

function normalizeCpf(value) {
  if (value == null || typeof value !== 'string') return '';
  const digits = value.replace(/\D/g, '');
  if (digits.length > 11) return digits.slice(0, 11);
  return digits.padStart(11, '0');
}

function parseDate(str) {
  if (!str || typeof str !== 'string') return null;
  const s = str.trim();
  const match = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) return null;
  const [, y, m, d] = match;
  const date = new Date(parseInt(y, 10), parseInt(m, 10) - 1, parseInt(d, 10));
  return isNaN(date.getTime()) ? null : date;
}

function trim(s) {
  return (s != null && typeof s === 'string') ? s.trim() : '';
}

function rowToMember(row, index) {
  const cpf = normalizeCpf(row.CPF ?? row.cpf ?? '');
  const hasCpf = cpf.length === 11;
  const nome = trim(row.NOME_COMPLETO ?? row.nome ?? row.NOME ?? '');
  const dataNasc = parseDate(row.DATA_NASCIMENTO ?? row.data_nascimento ?? '');
  const criadoEm = parseDate(row.CRIADO_EM ?? row.criado_em ?? '');
  const statusOrig = (row.STATUS ?? row.status ?? 'Ativo').toString().trim().toLowerCase();
  const status = statusOrig === 'ativo' ? 'ativo' : (hasCpf ? 'ativo' : 'pendente');

  const base = {
    NOME_COMPLETO: nome || 'Sem nome',
    EMAIL: trim(row.EMAIL ?? row.email ?? ''),
    TELEFONES: trim(row.TELEFONES ?? row.telefones ?? ''),
    SEXO: trim(row.SEXO ?? row.sexo ?? ''),
    FAIXA_ETARIA: trim(row.FAIXA_ETARIA ?? row.faixa_etaria ?? ''),
    IDADE: parseInt(row.IDADE ?? row.idade ?? '0', 10) || 0,
    ENDERECO: trim(row.ENDERECO ?? row.endereco ?? ''),
    CEP: trim(row.CEP ?? row.cep ?? ''),
    CIDADE: trim(row.CIDADE ?? row.cidade ?? ''),
    BAIRRO: trim(row.BAIRRO ?? row.bairro ?? ''),
    ESTADO_CIVIL: trim(row.ESTADO_CIVIL ?? row.estado_civil ?? ''),
    ESCOLARIDADE: trim(row.ESCOLARIDADE ?? row.escolaridade ?? ''),
    NOME_CONJUGE: trim(row.NOME_CONJUGE ?? row.nome_conjuge ?? ''),
    FILIACAO: trim(row.FILIACAO ?? row.filiacao ?? ''),
    FOTO_URL_OU_ID: trim(row.FOTO_URL_OU_ID ?? row.foto_url_ou_id ?? ''),
    DEPARTAMENTOS: Array.isArray(row.DEPARTAMENTOS) ? row.DEPARTAMENTOS : [],
    STATUS: hasCpf ? status : 'pendente',
    status: hasCpf ? status : 'pendente',
    IMPORTADO_EM: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (dataNasc) base.DATA_NASCIMENTO = admin.firestore.Timestamp.fromDate(dataNasc);
  if (criadoEm) base.CRIADO_EM = admin.firestore.Timestamp.fromDate(criadoEm);
  if (hasCpf) {
    base.CPF = cpf;
    base.MEMBER_ID = cpf;
  } else {
    base.CPF = '';
    base.MEMBER_ID = `pendente_${index}`;
  }

  return { hasCpf, docId: hasCpf ? cpf : `pendente_${index}`, data: base };
}

async function run() {
  const csvName = 'PLANILHA_SISTEMA_IGREJA_BPC_DB_V3 - MEMBERS.csv';
  const dirInProject = path.join(process.cwd(), 'membros_igrebrasilparacristo', csvName);
  const dirInScripts = path.join(process.cwd(), '..', 'membros_igrebrasilparacristo', csvName);
  const defaultCsv = fs.existsSync(dirInProject) ? dirInProject : dirInScripts;
  const csvPath = process.argv[2] || defaultCsv;
  if (!fs.existsSync(csvPath)) {
    console.error('Arquivo não encontrado:', csvPath);
    console.error('Uso: node import-members-bpc.js "<caminho-do-csv>"');
    process.exit(1);
  }

  if (!admin.apps.length) {
    try {
      admin.initializeApp({ projectId: 'gestaoyahweh-21e23' });
    } catch (e) {
      console.error('Firebase Admin: use GOOGLE_APPLICATION_CREDENTIALS com a chave do projeto gestaoyahweh-21e23.');
      throw e;
    }
  }

  const db = admin.firestore();
  const col = db.collection('tenants').doc(TENANT_ID).collection('members');

  const csvContent = fs.readFileSync(csvPath, { encoding: 'utf8' });
  const records = await new Promise((resolve, reject) => {
    parse(csvContent, {
      columns: true,
      skip_empty_lines: true,
      trim: true,
      relax_column_count: true,
      bom: true,
    }, (err, out) => (err ? reject(err) : resolve(out)));
  });

  let imported = 0;
  let pending = 0;
  const seen = new Set();
  let batch = db.batch();
  let batchCount = 0;

  for (let i = 0; i < records.length; i++) {
    const { hasCpf, docId, data } = rowToMember(records[i], i + 1);
    if (seen.has(docId)) continue;
    seen.add(docId);

    const ref = col.doc(docId);
    batch.set(ref, data, { merge: true });
    batchCount++;
    if (hasCpf) imported++; else pending++;

    if (batchCount >= BATCH_SIZE) {
      await batch.commit();
      console.log('Commit batch:', i + 1, 'linhas processadas');
      batch = db.batch();
      batchCount = 0;
    }
  }
  if (batchCount > 0) await batch.commit();

  // ——— Login para membros com CPF: Auth + publicCpfIndex + usersIndex (senha 123456, exceto CPF_MASTER)
  const auth = admin.auth();
  let authCreated = 0;
  let authSkipped = 0;
  for (let i = 0; i < records.length; i++) {
    const { hasCpf, data } = rowToMember(records[i], i + 1);
    if (!hasCpf) continue;
    const cpf = data.CPF;
    const nome = (data.NOME_COMPLETO || 'Membro').trim();
    const emailFromCsv = (data.EMAIL || '').trim();
    const isMasterCpf = cpf === CPF_MASTER;
    const email = isMasterCpf
      ? 'raihom@gmail.com'
      : ((emailFromCsv && emailFromCsv.includes('@')) ? emailFromCsv : `${cpf}@${MEMBRO_EMAIL_DOMAIN}`);

    const publicCpfRef = db.doc(`publicCpfIndex/${cpf}`);
    const usersIndexRef = db.collection('tenants').doc(TENANT_ID).collection('usersIndex').doc(cpf);
    await publicCpfRef.set({
      tenantId: TENANT_ID,
      churchId: TENANT_ID,
      cpf,
      email: email.toLowerCase(),
      name: nome,
      slug: TENANT_ID,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await usersIndexRef.set({
      cpf,
      email: email.toLowerCase(),
      name: nome,
      nome: nome,
      tenantId: TENANT_ID,
      role: isMasterCpf ? 'GESTOR' : 'user',
      active: true,
      ativo: true,
      mustCompleteRegistration: isMasterCpf ? false : true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    if (isMasterCpf) {
      authSkipped++;
      continue;
    }

    try {
      let uid;
      try {
        const existing = await auth.getUserByEmail(email);
        uid = existing.uid;
        await auth.updateUser(uid, { password: SENHA_PROVISORIA });
      } catch (_) {
        const created = await auth.createUser({
          email,
          password: SENHA_PROVISORIA,
          displayName: nome,
        });
        uid = created.uid;
      }
      await usersIndexRef.update({ uid });
      await db.collection('users').doc(uid).set({
        uid,
        cpf,
        email: email.toLowerCase(),
        name: nome,
        nome: nome,
        tenantId: TENANT_ID,
        igrejaId: TENANT_ID,
        role: 'user',
        ativo: true,
        active: true,
        mustCompleteRegistration: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      await auth.setCustomUserClaims(uid, {
        role: 'user',
        igrejaId: TENANT_ID,
        active: true,
      });
      authCreated++;
    } catch (e) {
      console.warn('Auth para', cpf, email, e?.message || e);
    }
  }

  console.log('Concluído.');
  console.log('Com CPF (ativos):', imported);
  console.log('Sem CPF (pendentes para atualização):', pending);
  console.log('Logins criados/atualizados (senha', SENHA_PROVISORIA + '):', authCreated);
  console.log('CPF', CPF_MASTER, 'não alterado (já tem senha).');
  console.log('Igreja: Brasil para Cristo — tenant:', TENANT_ID);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
