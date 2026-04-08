/**
 * Script de migração: sincroniza usuários (collection users) para membros da igreja
 * (tenants/{id}/members e igrejas/{id}/members). Execute na pasta functions:
 *
 *   node scripts/sync-members.js
 *
 * Requer credenciais: GOOGLE_APPLICATION_CREDENTIALS apontando para chave de conta de serviço
 * ou "gcloud auth application-default login". ProjectId: GCLOUD_PROJECT ou default do .firebaserc.
 */

const admin = require('firebase-admin');
const path = require('path');

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'gestaoyahweh-21e23';

if (!admin.apps.length) {
  try {
    admin.initializeApp({ projectId });
  } catch (e) {
    console.error('Erro ao inicializar Firebase Admin. Defina GOOGLE_APPLICATION_CREDENTIALS ou execute: gcloud auth application-default login');
    process.exit(1);
  }
}

const db = admin.firestore();

function run() {
  return db.collection('users').get()
    .then((usersSnap) => {
      let totalWritten = 0;
      const tenantIdsWritten = new Set();
      const igrejaIdsWritten = new Set();

      const promises = [];
      usersSnap.docs.forEach((userDoc) => {
        const uid = userDoc.id;
        const u = userDoc.data() || {};
        const tenantId = String(u.tenantId ?? u.tenant_id ?? '').trim();
        const igrejaId = String(u.igrejaId ?? u.igreja_id ?? '').trim();
        if (!tenantId && !igrejaId) return;

        const nome = String(u.nome ?? u.name ?? u.displayName ?? u.NOME_COMPLETO ?? '').trim() || 'Membro';
        const email = String(u.email ?? u.Email ?? u.EMAIL ?? '').trim();
        const cpf = String(u.cpf ?? u.CPF ?? '').replace(/\D/g, '').trim();
        const photoUrl = String(u.photoUrl ?? u.fotoUrl ?? u.photoURL ?? u.avatarUrl ?? u.imageUrl ?? u.FOTO_URL_OU_ID ?? '').trim();
        const status = u.ativo === false || u.active === false ? 'inativo' : 'ativo';
        const sexo = String(u.SEXO ?? u.sexo ?? u.genero ?? '').trim();
        const dataNasc = u.DATA_NASCIMENTO ?? u.dataNascimento ?? u.birthDate ?? null;

        const memberPayload = {
          authUid: uid,
          NOME_COMPLETO: nome,
          nome,
          name: nome,
          EMAIL: email,
          email,
          CPF: cpf,
          cpf,
          STATUS: status,
          status,
          tenantId: tenantId || igrejaId,
          igrejaId: igrejaId || tenantId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          syncedFromUsersAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (sexo) {
          memberPayload.SEXO = sexo;
          memberPayload.sexo = sexo;
        }
        if (dataNasc !== undefined && dataNasc !== null) {
          memberPayload.DATA_NASCIMENTO = dataNasc;
          memberPayload.dataNascimento = dataNasc;
        }
        if (photoUrl && (photoUrl.startsWith('http://') || photoUrl.startsWith('https://'))) {
          memberPayload.FOTO_URL_OU_ID = photoUrl;
          memberPayload.fotoUrl = photoUrl;
          memberPayload.photoUrl = photoUrl;
        }

        const idsToSync = new Set();
        if (tenantId) idsToSync.add(tenantId);
        if (igrejaId) idsToSync.add(igrejaId);

        idsToSync.forEach((churchId) => {
          if (!churchId) return;
          const tenantRef = db.collection('tenants').doc(churchId).collection('members').doc(uid);
          promises.push(
            tenantRef.set(memberPayload, { merge: true })
              .then(() => {
                tenantIdsWritten.add(churchId);
                totalWritten++;
              })
              .catch((err) => console.warn('Tenant members', churchId, uid, err.message))
          );
          const igrejaRef = db.collection('igrejas').doc(churchId).collection('members').doc(uid);
          promises.push(
            igrejaRef.set(memberPayload, { merge: true })
              .then(() => {
                igrejaIdsWritten.add(churchId);
                totalWritten++;
              })
              .catch((err) => console.warn('Igrejas members', churchId, uid, err.message))
          );
        });
      });

      return Promise.all(promises).then(() => ({
        usersProcessed: usersSnap.size,
        membersWritten: totalWritten,
        tenantsUpdated: Array.from(tenantIdsWritten),
        igrejasUpdated: Array.from(igrejaIdsWritten),
      }));
    });
}

run()
  .then((result) => {
    console.log('Migração concluída.');
    console.log('Usuários processados:', result.usersProcessed);
    console.log('Documentos de membros escritos:', result.membersWritten);
    console.log('Tenants atualizados:', result.tenantsUpdated.length);
    console.log('Igrejas atualizadas:', result.igrejasUpdated.length);
    process.exit(0);
  })
  .catch((err) => {
    console.error('Erro na migração:', err);
    process.exit(1);
  });
