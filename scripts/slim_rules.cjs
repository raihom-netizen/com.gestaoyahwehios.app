/**
 * Compactar firestore.rules para passar no validation engine (timeout 503).
 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const src = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');

let c = src;

// 1. Remover comentários de linha
c = c.replace(/\/\/[^\n]*/g, '');

// 2. Remover comentários de bloco
c = c.replace(/\/\*[\s\S]*?\*\//g, '');

// 3. Remover linhas em branco consecutivas
c = c.replace(/\n\s*\n/g, '\n');

// 4. Remover espaços em branco no fim das linhas
c = c.replace(/[ \t]+$/gm, '');

// 5. Simplificar tenantValueMatches — remover os 4 regex pesados
c = c.replace(
  /function tenantValueMatches\(value, tenantId\) \{[\s\S]*?\}/,
  'function tenantValueMatches(value, tenantId) {\n' +
  '  return value is string && (\n' +
  '    value == tenantId\n' +
  "    || value == ('id_' + tenantId)\n" +
  "    || value == ('v_' + tenantId)\n" +
  "    || tenantId == ('id_' + value)\n" +
  "    || tenantId == ('v_' + value)\n" +
  '  );\n' +
  '}'
);

// 6. Simplificar canManageChurch — usar toLower
c = c.replace(
  /function canManageChurch\(\) \{[\s\S]*?\}/,
  'function canManageChurch() {\n' +
  '  return isSignedIn() && role() != null && (\n' +
  "    role().toLower() == 'admin' || role().toLower() == 'adm' ||\n" +
  "    role().toLower() == 'gestor' || role().toLower() == 'master' ||\n" +
  "    role().toLower() == 'administrador' || role().toLower() == 'administradora'\n" +
  '  );\n' +
  '}'
);

// 7. Simplificar isAdm
c = c.replace(
  /function isAdm\(\) \{[\s\S]*?\}/,
  'function isAdm() {\n' +
  '  return isSignedIn() && role() != null && (\n' +
  "    role().toLower() == 'adm' || role().toLower() == 'admin' ||\n" +
  "    role().toLower() == 'administrador' || role().toLower() == 'administradora'\n" +
  '  );\n' +
  '}'
);

// 8. Simplificar isTreasurer
c = c.replace(
  /function isTreasurer\(\) \{[\s\S]*?\}/,
  'function isTreasurer() {\n' +
  '  return isSignedIn() && role() != null && (\n' +
  "    role().toLower() == 'tesoureiro' || role().toLower() == 'tesouraria'\n" +
  '  );\n' +
  '}'
);

// 9. Simplificar isDepartmentLeaderRole
c = c.replace(
  /function isDepartmentLeaderRole\(\) \{[\s\S]*?\}/,
  'function isDepartmentLeaderRole() {\n' +
  '  let r = role();\n' +
  '  return r != null && (\n' +
  "    r.toLower() == 'lider' || r.toLower() == 'lider_departamento' ||\n" +
  "    r.toLower() == 'lider_depto' || r.toLower() == 'lider_grupo' ||\n" +
  "    r.toLower() == 'lider de grupo' || r.toLower() == 'lider_de_grupo'\n" +
  '  );\n' +
  '}'
);

// 10. Simplificar isPastorAuxiliarRole
c = c.replace(
  /function isPastorAuxiliarRole\(\) \{[\s\S]*?\}/,
  'function isPastorAuxiliarRole() {\n' +
  '  let r = role();\n' +
  '  return r != null && (\n' +
  "    r.toLower() == 'pastor_auxiliar' || r.toLower() == 'ministerial' ||\n" +
  "    r.toLower() == 'pastor_auxiliar_ministerial'\n" +
  '  );\n' +
  '}'
);

// 11. Remover múltiplos espaços consecutivos
c = c.replace(/  +/g, ' ');

// 12. Remover espaços antes de { e depois de }
c = c.replace(/\s*\{/g, ' {').replace(/\}\s*/g, '} ');

// 13. Limpar linhas em branco consecutivas
c = c.replace(new RegExp('\\n\\s*\\n', 'g'), '\n').trim() + '\n';

const outFile = path.join(root, 'firestore.rules.slim');
fs.writeFileSync(outFile, c);

console.log('Original: ' + src.length + ' bytes (' + src.split('\n').length + ' lines)');
console.log('Slim: ' + c.length + ' bytes (' + c.split('\n').length + ' lines)');
console.log('Saved: ' + (src.length - c.length) + ' bytes (' + Math.round((1 - c.length / src.length) * 100) + '%)');
