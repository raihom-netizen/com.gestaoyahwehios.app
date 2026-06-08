#!/usr/bin/env node
/**
 * Em métodos async, adiciona resolveCached antes de churchDoc(tenantId|widget.tenantId|tid|_tid|igrejaId|churchId|slug)
 */
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(import.meta.dirname, '..', 'flutter_app', 'lib');
const EXCLUDE = [
  'tenant_resolver_service.dart',
  'church_tenant_resilient_reads.dart',
  'church_operational_paths.dart',
  'multi_tenant_diagnostic_service.dart',
  'jimsabores_frota',
];

const VARS = [
  'tenantId',
  'widget.tenantId',
  'widget.tenantId!',
  '_tenantId!',
  '_tenantId',
  '_tid',
  'tid',
  'igrejaId',
  'churchId',
  'slug',
  'seed',
  'resolvedTenantId',
  'targetTenantId',
  'igrejaDocId',
];

function shouldSkip(p) {
  return EXCLUDE.some((e) => p.includes(e.replace(/\//g, path.sep)));
}

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (!shouldSkip(p)) walk(p, out);
    } else if (ent.name.endsWith('.dart') && !shouldSkip(p)) out.push(p);
  }
  return out;
}

function processFile(filePath) {
  let lines = fs.readFileSync(filePath, 'utf8').split('\n');
  let changed = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line.includes('ChurchOperationalPaths.churchDoc(')) continue;

    // já tem resolve na função?
    let fnStart = i;
    while (fnStart > 0 && !lines[fnStart].match(/^\s*(Future|static Future|async)/)) {
      if (lines[fnStart].match(/^\s*(void|String|int|bool|Widget|Stream|CollectionReference|DocumentReference)/)) break;
      fnStart--;
    }
    const fnBlock = lines.slice(fnStart, i + 1).join('\n');
    if (fnBlock.includes('resolveCached(') || fnBlock.includes('resolveOperationalChurchDocId(')) continue;
    if (!fnBlock.includes('async')) continue;

    for (const v of VARS) {
      const re = new RegExp(`ChurchOperationalPaths\\.churchDoc\\(${v.replace('.', '\\.')}(?:\\.trim\\(\\))?\\)`);
      if (!re.test(line) && !lines.slice(i, i + 3).join(' ').match(re)) continue;

      const seedExpr = v.includes('widget.') ? v : v;
      const indent = line.match(/^(\s*)/)[1];
      const resolveLine = `${indent}final op = await ChurchOperationalPaths.resolveCached(${seedExpr}${v.includes('!') ? '' : '.trim()'});`;
      // evita duplicar
      if (lines[i - 1]?.includes('resolveCached(')) break;
      lines.splice(i, 0, resolveLine);
      // substituir churchDoc(var) por churchDoc(op) nas próximas linhas do bloco
      for (let j = i + 1; j < Math.min(i + 15, lines.length); j++) {
        lines[j] = lines[j].replace(
          new RegExp(`ChurchOperationalPaths\\.churchDoc\\(${v.replace('.', '\\.')}(?:\\.trim\\(\\))?\\)`, 'g'),
          'ChurchOperationalPaths.churchDoc(op)',
        );
      }
      changed = true;
      i++;
      break;
    }
  }

  if (changed) {
    fs.writeFileSync(filePath, lines.join('\n'), 'utf8');
    return true;
  }
  return false;
}

const migrated = [];
for (const f of walk(ROOT)) {
  const c = fs.readFileSync(f, 'utf8');
  if (!c.includes('ChurchOperationalPaths.churchDoc')) continue;
  if (processFile(f)) migrated.push(path.relative(ROOT, f).replace(/\\/g, '/'));
}
console.log(`Added resolveCached in ${migrated.length} files`);
migrated.forEach((x) => console.log('  ' + x));
