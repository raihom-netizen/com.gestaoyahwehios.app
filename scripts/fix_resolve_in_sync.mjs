#!/usr/bin/env node
/** Remove resolveCached inserido em getters/funções síncronas */
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(import.meta.dirname, '..', 'flutter_app', 'lib');
const RESOLVE_RE =
  /^\s*final op = await ChurchOperationalPaths\.resolveCached\([^)]+\);\s*$/;

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, out);
    else if (ent.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

let fixed = 0;
for (const f of walk(ROOT)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  let changed = false;
  for (let i = 0; i < lines.length; i++) {
    if (!RESOLVE_RE.test(lines[i])) continue;
    // contexto: linha anterior termina com => ou { sem async na assinatura
    let j = i - 1;
    while (j >= 0 && lines[j].trim() === '') j--;
    const prev = j >= 0 ? lines[j] : '';
    const prev2 = j >= 1 ? lines[j - 1] : '';
    const isSyncGetter =
      prev.trimEnd().endsWith('=>') ||
      (prev.includes('get ') && !prev.includes('async')) ||
      (prev2.includes('get ') && prev.trim() === '');
    const isSyncFn =
      /^\s*(?:static\s+)?(?:CollectionReference|DocumentReference|Stream|Widget|bool|int|String|double|List|Map|FirebaseFirestore)/.test(
        prev,
      ) && !prev.includes('async') && !prev.includes('Future');
    if (!isSyncGetter && !isSyncFn) continue;

    lines.splice(i, 1);
    changed = true;
    // restaurar churchDoc(op) -> churchDoc(param) nas próximas linhas
    for (let k = i; k < Math.min(i + 8, lines.length); k++) {
      if (lines[k].includes('churchDoc(op)')) {
        // tenta inferir param da linha removida — usar tenantId genérico já no escopo
        break;
      }
    }
    i--;
  }

  if (changed) {
    let content = lines.join('\n');
    // em getters síncronos, op sem resolve vira erro — trocar churchDoc(op) por churchDoc original
    // heurística: churchDoc(op) em arquivo com getter sync -> manter param do método
    fs.writeFileSync(f, content, 'utf8');
    fixed++;
    console.log(path.relative(ROOT, f).replace(/\\/g, '/'));
  }
}

// segunda passagem: churchDoc(op) em funções que recebem tenantId mas sem resolve
for (const f of walk(ROOT)) {
  let c = fs.readFileSync(f, 'utf8');
  const orig = c;
  // _col(String tenantId) => ... churchDoc(op) sem resolve acima
  c = c.replace(
    /(\([^)]*tenantId[^)]*\)\s*=>\s*\n)\s*ChurchOperationalPaths\.churchDoc\(op\)/g,
    '$1      ChurchOperationalPaths.churchDoc(tenantId.trim())',
  );
  c = c.replace(
    /(\([^)]*operationalTenantId[^)]*\)\s*=>\s*\n)\s*ChurchOperationalPaths\.churchDoc\(op\)/g,
    '$1      ChurchOperationalPaths.churchDoc(operationalTenantId.trim())',
  );
  c = c.replace(
    /(get _\w+ =>\s*\n)\s*ChurchOperationalPaths\.churchDoc\(op\)/g,
    '$1      ChurchOperationalPaths.churchDoc(widget.tenantId)',
  );
  if (c !== orig) {
    fs.writeFileSync(f, c, 'utf8');
    if (!fixed) console.log('pass2: ' + path.relative(ROOT, f).replace(/\\/g, '/'));
  }
}

console.log(`Fixed sync contexts in ${fixed} files`);
