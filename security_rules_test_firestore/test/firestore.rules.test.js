import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
const projectId = 'gestao-yahweh-rules-test';

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment} */
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

describe('Firestore Security Rules — Gestão YAHWEH (smoke)', () => {
  test('visitante não autenticado não lê membros do tenant', async () => {
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(
      ctx.firestore().doc('igrejas/igreja_teste/membros/membro_x').get(),
    );
  });

  test('utilizador autenticado lê doc raiz da própria igreja (tenant claim)', async () => {
    const ctx = testEnv.authenticatedContext('uid_membro', {
      email: 'membro@teste.local',
      igrejaId: 'igreja_teste',
      role: 'membro',
    });
    await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
      await adminCtx.firestore().doc('igrejas/igreja_teste').set({
        nome: 'Igreja Teste',
        ativo: true,
      });
    });
    await assertSucceeds(
      ctx.firestore().doc('igrejas/igreja_teste').get(),
    );
  });

  test('bloqueia escrita em coleção legada tenants', async () => {
    const ctx = testEnv.authenticatedContext('uid_gestor', {
      email: 'gestor@teste.local',
      igrejaId: 'igreja_teste',
      role: 'gestor',
    });
    await assertFails(
      ctx.firestore().collection('tenants').doc('x').set({ nome: 'hack' }),
    );
  });
});
