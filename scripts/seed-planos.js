/**
 * Semeia planos em config/plans/items para a Assinatura funcionar.
 * IDs devem coincidir com lib/data/planos_oficiais.dart (inicial, essencial, etc.).
 * Uso: node seed-planos.js
 * Requer GOOGLE_APPLICATION_CREDENTIALS ou secrets/gestaoyahweh-*.json
 */

import admin from 'firebase-admin';
import path from 'path';
import fs from 'fs';

const PLANS = [
  { id: 'inicial', name: 'Plano Inicial', membersMax: 100, priceMonthly: 59.9, priceAnnual: 599 },
  { id: 'essencial', name: 'Plano Essencial', membersMax: 150, priceMonthly: 69.9, priceAnnual: 699 },
  { id: 'intermediario', name: 'Plano Intermediário', membersMax: 250, priceMonthly: 79.9, priceAnnual: 799 },
  { id: 'avancado', name: 'Plano Avançado', membersMax: 350, priceMonthly: 99.9, priceAnnual: 999 },
  { id: 'profissional', name: 'Plano Profissional', membersMax: 400, priceMonthly: 109.9, priceAnnual: 1099 },
  { id: 'premium', name: 'Plano Premium', membersMax: 500, priceMonthly: 179.9, priceAnnual: 1799 },
  { id: 'premium_plus', name: 'Plano Premium Plus', membersMax: 600, priceMonthly: 199.9, priceAnnual: 1999 },
  { id: 'corporativo', name: 'Plano Corporativo', membersMax: 9999, priceMonthly: null, priceAnnual: null },
];

async function run() {
  if (!admin.apps.length) {
    const keyPath = path.join(process.cwd(), '..', 'secrets', 'gestaoyahweh-21e23-7951f1817911.json');
    if (fs.existsSync(keyPath)) process.env.GOOGLE_APPLICATION_CREDENTIALS = keyPath;
    admin.initializeApp({ projectId: 'gestaoyahweh-21e23' });
  }
  const db = admin.firestore();
  const col = db.collection('config').doc('plans').collection('items');
  for (const p of PLANS) {
    await col.doc(p.id).set({
      name: p.name,
      membersMax: p.membersMax,
      priceMonthly: p.priceMonthly ?? 0,
      priceAnnual: p.priceAnnual ?? 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log('Plano', p.id, p.name, '- OK');
  }
  console.log('Planos semeados (IDs alinhados ao app). Acesse Assinatura no painel.');
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
