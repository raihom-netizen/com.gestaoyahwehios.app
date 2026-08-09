'use strict';
/**
 * Conta documentos das subcoleções da igreja (ground truth) via Firestore REST.
 * NÃO altera nada — somente leitura.
 */
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));

const projectId = 'gestaoyahweh-21e23';
const churchId = 'igreja_o_brasil_para_cristo_jardim_goiano';
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

const subs = [
  'patrimonio', 'fornecedores', 'membros', 'finance', 'aprovacoes',
  'certificados', 'cartas', 'cartao', 'eventos', 'avisos', 'escalas',
];

async function countSub(token, sub) {
  const H = { Authorization: `Bearer ${token}` };
  // pageSize alto para contar rápido; só precisamos de existência/qtd aproximada
  let url = `${base}/igrejas/${churchId}/${sub}?pageSize=300`;
  let total = 0;
  let firstNames = [];
  try {
    const res = await fetch(url, { headers: H });
    if (!res.ok) {
      return { sub, err: `HTTP ${res.status}` };
    }
    const j = await res.json();
    const docs = j.documents || [];
    total += docs.length;
    firstNames = docs.slice(0, 3).map((d) => {
      const f = d.fields || {};
      const nome = f.nome?.stringValue || f.titulo?.stringValue || f.name?.stringValue || d.name.split('/').pop();
      return nome;
    });
    return { sub, total, firstNames, more: !!j.nextPageToken };
  } catch (e) {
    return { sub, err: e.message };
  }
}

async function main() {
  const { token, source } = await getAccessToken();
  console.log(`token OK (source=${source})`);
  console.log(`igreja: ${churchId}\n`);
  for (const sub of subs) {
    const r = await countSub(token, sub);
    if (r.err) {
      console.log(`  ${sub.padEnd(14)} -> ERRO ${r.err}`);
    } else {
      console.log(`  ${sub.padEnd(14)} -> ${r.total}${r.more ? '+' : ''} docs   ${r.firstNames.length ? '[' + r.firstNames.join(', ') + ']' : ''}`);
    }
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
