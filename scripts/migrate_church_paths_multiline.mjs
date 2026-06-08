#!/usr/bin/env node
/** Migra padrões multilinha .collection('igrejas')\n.doc(x) restantes */
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
const IMPORT =
  "import 'package:gestao_yahweh/services/church_operational_paths.dart';";

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

function addImport(content) {
  if (content.includes('church_operational_paths.dart')) return content;
  const lines = content.split('\n');
  let lastImport = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('import ')) lastImport = i;
  }
  if (lastImport >= 0) {
    lines.splice(lastImport + 1, 0, IMPORT);
    return lines.join('\n');
  }
  return IMPORT + '\n' + content;
}

// db\n.collection('igrejas')\n.doc(x) — remove db prefix too
const MULTI_WITH_PREFIX =
  /(?:FirebaseFirestore\.instance|firebaseDefaultFirestore|_db|_fs|db|firestore)\s*\n\s*\.collection\('igrejas'\)\s*\n\s*\.doc\(([^)]+)\)/g;

const MULTI_DOC =
  /\.collection\('igrejas'\)\s*\n\s*\.doc\(([^)]+)\)/g;

const migrated = [];
for (const f of walk(ROOT)) {
  let c = fs.readFileSync(f, 'utf8');
  if (!c.includes("collection('igrejas')")) continue;
  const orig = c;
  c = c.replace(MULTI_WITH_PREFIX, 'ChurchOperationalPaths.churchDoc($1)');
  c = c.replace(MULTI_DOC, 'ChurchOperationalPaths.churchDoc($1)');
  if (c !== orig) {
    c = addImport(c);
    fs.writeFileSync(f, c, 'utf8');
    migrated.push(path.relative(ROOT, f).replace(/\\/g, '/'));
  }
}
console.log(`Migrated ${migrated.length} files`);
migrated.forEach((x) => console.log('  ' + x));
