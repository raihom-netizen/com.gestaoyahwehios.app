// Atualiza os preços dos planos (por membros) no override Firestore
// `config/plans/items/{planId}.priceMonthly`. Isso sincroniza INSTANTANEAMENTE
// web + Android + iOS + checkout (PIX/cartão) + divulgação, sem depender de
// deploy (o app lê o override via PlanPriceService). Anual = mensal × 10 (fixo).
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');

admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();

// Nova tabela (mensal). Anual sai automático = ×10 no app.
const PLANS = [
  { id: 'inicial',       priceMonthly: 59.90,  maxMembers: 100,    name: 'Plano Inicial',         members: 'Até 100 membros' },
  { id: 'essencial',     priceMonthly: 79.90,  maxMembers: 150,    name: 'Plano Essencial',       members: '100 a 150 membros' },
  { id: 'intermediario', priceMonthly: 99.90,  maxMembers: 250,    name: 'Plano Intermediário',   members: '150 a 250 membros' },
  { id: 'avancado',      priceMonthly: 129.90, maxMembers: 350,    name: 'Plano Avançado',        members: '250 a 350 membros' },
  { id: 'profissional',  priceMonthly: 149.90, maxMembers: 400,    name: 'Plano Profissional',    members: '350 a 400 membros' },
  { id: 'premium',       priceMonthly: 179.90, maxMembers: 500,    name: 'Plano Premium',         members: '400 a 500 membros' },
  { id: 'premium_plus',  priceMonthly: 219.90, maxMembers: 600,    name: 'Plano Premium Plus',    members: '500 a 600 membros' },
  { id: 'corporativo_i', priceMonthly: 299.90, maxMembers: 1000,   name: 'Plano Corporativo',     members: '600 a 1000 membros' },
  // Acima de 1000: "a combinar" — remove priceMonthly do override (usa null do código).
  { id: 'corporativo',   priceMonthly: null,   maxMembers: 100000, name: 'Plano Corporativo Plus', members: 'Acima de 1000 membros' },
];

(async () => {
  const col = db.collection('config').doc('plans').collection('items');
  for (const p of PLANS) {
    const ref = col.doc(p.id);
    const payload = {
      name: p.name,
      members: p.members,
      maxMembers: p.maxMembers,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (p.priceMonthly == null) {
      payload.priceMonthly = admin.firestore.FieldValue.delete();
    } else {
      payload.priceMonthly = p.priceMonthly;
    }
    await ref.set(payload, { merge: true });
    const anual = p.priceMonthly == null ? '(a combinar)' : (p.priceMonthly * 10).toFixed(2);
    console.log(`OK ${p.id}: mensal ${p.priceMonthly == null ? '(a combinar)' : p.priceMonthly} | anual ${anual}`);
  }
  console.log('\nTodos os planos atualizados em config/plans/items. Sincroniza web/Android/iOS/checkout/divulgação sem deploy.');
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e); process.exit(1); });
