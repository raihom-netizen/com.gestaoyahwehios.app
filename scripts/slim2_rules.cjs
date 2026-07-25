/**
 * Agressivamente compactar firestore.rules para <50KB.
 * Mantém toda a segurança, apenas consolida e simplifica.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
let c = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');

// 1. Remover TODOS os comentários
c = c.replace(/\/\/[^\n]*/g, '');
c = c.replace(/\/\*[\s\S]*?\*\//g, '');

// 2. Remover linhas em branco
c = c.replace(/\n\s*\n/g, '\n');
c = c.replace(/[ \t]+$/gm, '');

// 3. tenantValueMatches — remover regexes
c = c.replace(
  /function tenantValueMatches\(value, tenantId\) \{[\s\S]*?\n\s*\}/,
  "function tenantValueMatches(value, tenantId) {\n  return value is string && (value == tenantId || value == ('id_' + tenantId) || value == ('v_' + tenantId) || tenantId == ('id_' + value) || tenantId == ('v_' + value));\n}"
);

// 4. Consolidar role checks — função helper para toLower
// Substituir TODAS as funções de role checking massivas

// canManageChurch
c = c.replace(
  /function canManageChurch\(\) \{[\s\S]*?\n\s*\}/,
  "function canManageChurch() {\n  let r = role();\n  return isSignedIn() && r != null && (r == 'ADMIN' || r == 'ADM' || r == 'GESTOR' || r == 'MASTER' || r == 'admin' || r == 'adm' || r == 'gestor' || r == 'master' || r == 'Admin' || r == 'Adm' || r == 'Gestor' || r == 'Master' || r == 'administrador' || r == 'administradora' || r == 'Administrador' || r == 'Administradora');\n}"
);

// isAdm
c = c.replace(
  /function isAdm\(\) \{[\s\S]*?\n\s*\}/,
  "function isAdm() {\n  let r = role();\n  return isSignedIn() && r != null && (r == 'ADM' || r == 'ADMIN' || r == 'adm' || r == 'admin' || r == 'Adm' || r == 'Admin' || r == 'administrador' || r == 'administradora' || r == 'Administrador' || r == 'Administradora');\n}"
);

// isTreasurer
c = c.replace(
  /function isTreasurer\(\) \{[\s\S]*?\n\s*\}/,
  "function isTreasurer() {\n  let r = role();\n  return isSignedIn() && r != null && (r == 'TESOUREIRO' || r == 'tesoureiro' || r == 'Tesoureiro' || r == 'TESOURARIA' || r == 'tesouraria' || r == 'Tesouraria');\n}"
);

// isDepartmentLeaderRole
c = c.replace(
  /function isDepartmentLeaderRole\(\) \{[\s\S]*?\n\s*\}/,
  "function isDepartmentLeaderRole() {\n  let r = role();\n  return r != null && (r == 'lider' || r == 'LIDER' || r == 'Lider' || r == 'l\u00EDder' || r == 'L\u00EDder' || r == 'L\u00CDDEr' || r == 'lider_departamento' || r == 'LIDER_DEPARTAMENTO' || r == 'lider_depto' || r == 'LIDER_DEPTO' || r == 'lider_grupo' || r == 'LIDER_GRUPO' || r == 'Lider grupo' || r == 'Lider Grupo' || r == 'L\u00EDder de grupo' || r == 'l\u00EDder de grupo' || r == 'Lider de grupo' || r == 'LIDER DE GRUPO' || r == 'lider_de_grupo' || r == 'LIDER_DE_GRUPO');\n}"
);

// isPastorAuxiliarRole
c = c.replace(
  /function isPastorAuxiliarRole\(\) \{[\s\S]*?\n\s*\}/,
  "function isPastorAuxiliarRole() {\n  let r = role();\n  return r != null && (r == 'pastor_auxiliar' || r == 'PASTOR_AUXILIAR' || r == 'Pastor Auxiliar' || r == 'ministerial' || r == 'pastor_auxiliar_ministerial');\n}"
);

// isMembroPortariaRole
c = c.replace(
  /function isMembroPortariaRole\(\) \{[\s\S]*?\n\s*\}/,
  "function isMembroPortariaRole() {\n  let r = role();\n  return r != null && (r == 'membro' || r == 'MEMBRO' || r == 'Membro' || r == 'visitante' || r == 'VISITANTE' || r == 'Visitante');\n}"
);

// isPastoralOrSecretariatRole
c = c.replace(
  /function isPastoralOrSecretariatRole\(\) \{[\s\S]*?\n\s*\}/,
  "function isPastoralOrSecretariatRole() {\n  let r = role();\n  return r != null && (r == 'PASTOR' || r == 'pastor' || r == 'PASTORA' || r == 'pastora' || r == 'Pastor' || r == 'Pastora' || r == 'pastor_presidente' || r == 'PASTOR_PRESIDENTE' || r == 'Pastor Presidente' || r == 'pastora_presidente' || r == 'SECRETARIO' || r == 'secretario' || r == 'SECRETARIO' || r == 'Secretario' || r == 'PRESBITERO' || r == 'presbitero' || r == 'PRESBITERA' || r == 'presbitera' || r == 'Presbitero' || r == 'Presbitera');\n}"
);

// isEventosMuralEditorRole
c = c.replace(
  /function isEventosMuralEditorRole\(\) \{[\s\S]*?\n\s*\}/,
  "function isEventosMuralEditorRole() {\n  let r = role();\n  return r != null && (r == 'lider' || r == 'LIDER' || r == 'Lider' || r == 'l\u00EDder' || r == 'L\u00CDDEr' || r == 'L\u00EDder' || r == 'lider_departamento' || r == 'LIDER_DEPARTAMENTO' || r == 'lider_depto' || r == 'LIDER_DEPTO' || r == 'lider_grupo' || r == 'LIDER_GRUPO' || r == 'Lider grupo' || r == 'Lider Grupo' || r == 'L\u00EDder de grupo' || r == 'l\u00EDder de grupo' || r == 'Lider de grupo' || r == 'LIDER DE GRUPO' || r == 'lider_de_grupo' || r == 'LIDER_DE_GRUPO' || r == 'tesoureiro' || r == 'TESOUREIRO' || r == 'Tesoureiro' || r == 'tesouraria' || r == 'TESOURARIA' || r == 'Tesouraria');\n}"
);

// isPastoralOrSecretariatMuralRole
c = c.replace(
  /function isPastoralOrSecretariatMuralRole\(\) \{[\s\S]*?\n\s*\}/,
  "function isPastoralOrSecretariatMuralRole() {\n  let r = role();\n  return r != null && (r == 'PASTOR' || r == 'pastor' || r == 'PASTORA' || r == 'pastora' || r == 'Pastor' || r == 'Pastora' || r == 'pastor_presidente' || r == 'PASTOR_PRESIDENTE' || r == 'Pastor Presidente' || r == 'pastora_presidente' || r == 'pastor_auxiliar' || r == 'PASTOR_AUXILIAR' || r == 'Pastor Auxiliar' || r == 'ministerial' || r == 'pastor_auxiliar_ministerial' || r == 'SECRETARIO' || r == 'secretario' || r == 'SECRETARIO' || r == 'Secretario' || r == 'secret\u00E1ria' || r == 'Secretaria');\n}"
);

// financeStaffRoleString — muito grande
c = c.replace(
  /function financeStaffRoleString\(r\) \{[\s\S]*?\n\s*\}/,
  "function financeStaffRoleString(r) {\n  return r != null && (r == 'MASTER' || r == 'master' || r == 'Master' || r == 'ADMIN' || r == 'ADM' || r == 'admin' || r == 'adm' || r == 'Adm' || r == 'Admin' || r == 'administrador' || r == 'administradora' || r == 'Administrador' || r == 'Administradora' || r == 'GESTOR' || r == 'gestor' || r == 'Gestor' || r == 'PASTOR' || r == 'pastor' || r == 'PASTORA' || r == 'pastora' || r == 'Pastor' || r == 'Pastora' || r == 'pastor_presidente' || r == 'PASTOR_PRESIDENTE' || r == 'pastora_presidente' || r == 'pastor_auxiliar' || r == 'PASTOR_AUXILIAR' || r == 'Pastor Auxiliar' || r == 'ministerial' || r == 'pastor_auxiliar_ministerial' || r == 'SECRETARIO' || r == 'secretario' || r == 'Secretario' || r == 'secret\u00E1ria' || r == 'Secretaria' || r == 'secretaria' || r == 'TESOUREIRO' || r == 'tesoureiro' || r == 'Tesoureiro' || r == 'TESOURARIA' || r == 'tesouraria' || r == 'Tesouraria');\n}"
);

// Remover espaços múltiplos
c = c.replace(/  +/g, ' ');
c = c.replace(/\s*\{/g, ' {');
c = c.replace(/\}\s*/g, '} ');
c = c.replace(new RegExp('\\n\\s*\\n', 'g'), '\n').trim() + '\n';

const outFile = path.join(root, 'firestore.rules.slim2');
fs.writeFileSync(outFile, c);
console.log('Original: ' + fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8').length + ' bytes');
console.log('Slim2: ' + c.length + ' bytes (' + c.split('\n').length + ' lines)');
console.log('Saved: ' + Math.round((1 - c.length / fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8').length) * 100) + '%');
