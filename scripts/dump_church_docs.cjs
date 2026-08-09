'use strict';
const path = require('path');
const { getAccessToken } = require(path.join(__dirname, 'gcp_rules_auth.cjs'));
const projectId = 'gestaoyahweh-21e23';
const churchId = 'igreja_o_brasil_para_cristo_jardim_goiano';
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function flat(fields, prefix = '') {
  const out = {};
  for (const [k, v] of Object.entries(fields || {})) {
    const key = prefix + k;
    if (v.mapValue) Object.assign(out, flat(v.mapValue.fields, key + '.'));
    else out[key] = v.stringValue ?? v.integerValue ?? v.doubleValue ?? v.booleanValue ?? v.timestampValue ?? (v.nullValue !== undefined ? null : JSON.stringify(v));
  }
  return out;
}

async function dump(token, sub) {
  const H = { Authorization: `Bearer ${token}` };
  const res = await fetch(`${base}/igrejas/${churchId}/${sub}?pageSize=5`, { headers: H });
  const j = await res.json();
  console.log(`\n===== ${sub} (${(j.documents||[]).length}) =====`);
  for (const d of (j.documents || [])) {
    console.log('  id:', d.name.split('/').pop());
    console.log('  fields:', JSON.stringify(flat(d.fields), null, 0));
  }
}

async function main() {
  const { token } = await getAccessToken();
  for (const s of ['patrimonio', 'fornecedores']) await dump(token, s);
}
main().catch(e => { console.error(e); process.exit(1); });
