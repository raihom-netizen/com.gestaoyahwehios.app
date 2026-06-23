#!/usr/bin/env node
'use strict';
/** Corrige mojibake UTF-8 em firestore.rules (comentários + strings de role). */
const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..');
const rulesPath = path.join(repoRoot, 'firestore.rules');

function applyManualReplacements(text) {
  const pairs = [
    ['GravaÃƒÂ§ÃƒÂ£o', 'Gravação'],
    ['padrÃƒÂ£o', 'padrão'],
    ['coleÃƒÂ§ÃƒÂµes', 'coleções'],
    ['negÃƒÂ³cio', 'negócio'],
    ['LÃƒÂ­der de Departamento', 'Líder de Departamento'],
    ['lÃƒÂ­der de departamento', 'líder de departamento'],
    ['LÃƒÂ­der de grupo', 'Líder de grupo'],
    ['lÃƒÂ­der de grupo', 'líder de grupo'],
    ['lÃƒÂ­der', 'líder'],
    ['LÃƒÂ­der', 'Líder'],
    ['LÃƒÂDER', 'LÍDER'],
    ['SecretÃƒÂ¡rio', 'Secretário'],
    ['SECRETÃƒÂRIO', 'SECRETÁRIO'],
    ['secretÃƒÂ¡ria', 'secretária'],
    ['SecretÃ¡rio', 'Secretário'],
    ['SECRETÃRIO', 'SECRETÁRIO'],
    ['secretÃ¡ria', 'secretária'],
    ['lÃ­der', 'líder'],
    ['LÃ­der', 'Líder'],
    ['LÃDER', 'LÍDER'],
    ['dÃ­gitos', 'dígitos'],
    ['nÃ£o', 'não'],
    ['sÃ³', 'só'],
    ['prÃ³pria', 'própria'],
    ['pÃºblico', 'público'],
    ['canÃ³nicos', 'canónicos'],
    ['aprovaÃ§Ã£o', 'aprovação'],
    ['secretÃ¡rio', 'secretário'],
    ['gestÃ£o', 'gestão'],
    ['ColeÃ§Ã£o', 'Coleção'],
    ['subcoleÃ§Ã£o', 'subcoleção'],
    ['coleÃ§Ãµes', 'coleções'],
    ['GravaÃ§Ã£o', 'Gravação'],
    ['padrÃ£o', 'padrão'],
    ['negÃ³cio', 'negócio'],
    ['patrimÃ³nio', 'património'],
    ['PermissÃµes', 'Permissões'],
    ['Ã© o', 'é o'],
    ['Ã© ', 'é '],
    ['â€"', '—'],
    ['â€¦', '…'],
    ['â†\'', '→'],
    ['Ã¢â€ â€™', '→'],
    ['Ã¢â€šÂ¬', ''],
    ['â"€â"€', '--'],
  ];
  let out = text;
  for (const [from, to] of pairs) {
    if (out.includes(from)) out = out.split(from).join(to);
  }
  return out;
}

const raw = fs.readFileSync(rulesPath, 'utf8');
let fixed = applyManualReplacements(raw);
fixed = fixed.replace(/\r\n/g, '\n');

const backup = rulesPath + '.bak-encoding-' + new Date().toISOString().slice(0, 10);
if (!fs.existsSync(backup)) fs.writeFileSync(backup, raw, 'utf8');

fs.writeFileSync(rulesPath, fixed, { encoding: 'utf8' });

const remaining = (fixed.match(/Ã|â€|â†|â"/g) || []).length;
process.stdout.write(
  JSON.stringify({
    ok: true,
    path: rulesPath,
    backup,
    bytesBefore: raw.length,
    bytesAfter: fixed.length,
    mojibakeTokensRemaining: remaining,
    sampleLine206: fixed.split('\n')[205],
  }, null, 2) + '\n'
);
