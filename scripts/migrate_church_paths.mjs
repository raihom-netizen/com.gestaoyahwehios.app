#!/usr/bin/env node
/**
 * Migra collection('igrejas').doc(...) → ChurchOperationalPaths.churchDoc(...)
 * e adiciona resolveCached onde tenantId ainda não foi resolvido.
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

const IMPORT =
  "import 'package:gestao_yahweh/services/church_operational_paths.dart';";

function shouldSkip(filePath) {
  return EXCLUDE.some((e) => filePath.includes(e.replace(/\//g, path.sep)));
}

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (!shouldSkip(p)) walk(p, out);
    } else if (ent.name.endsWith('.dart') && !shouldSkip(p)) {
      out.push(p);
    }
  }
  return out;
}

// Patterns: capture db prefix and tenant id variable
const DOC_PATTERNS = [
  // FirebaseFirestore.instance.collection('igrejas').doc(x)
  /FirebaseFirestore\.instance\.collection\('igrejas'\)\.doc\(([^)]+)\)/g,
  /firebaseDefaultFirestore\.collection\('igrejas'\)\.doc\(([^)]+)\)/g,
  /_db\.collection\('igrejas'\)\.doc\(([^)]+)\)/g,
  /_fs\.collection\('igrejas'\)\.doc\(([^)]+)\)/g,
  /db\.collection\('igrejas'\)\.doc\(([^)]+)\)/g,
  /firestore\.collection\('igrejas'\)\.doc\(([^)]+)\)/g,
];

// Multi-line: .collection('igrejas')\n        .doc(x)
const MULTILINE_DOC =
  /\.collection\('igrejas'\)\s*\n\s*\.doc\(([^)]+)\)/g;

// Master-level: keep .collection('igrejas').get() / .watchSafe() / .where without doc
const MASTER_KEEP =
  /collection\('igrejas'\)\s*\.(get|watchSafe|where|limit|snapshots)\(/;

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

function migrateFile(filePath) {
  let content = fs.readFileSync(filePath, 'utf8');
  if (!content.includes("collection('igrejas')")) return false;

  const original = content;

  // Replace single-line doc patterns
  for (const re of DOC_PATTERNS) {
    content = content.replace(re, 'ChurchOperationalPaths.churchDoc($1)');
  }
  content = content.replace(MULTILINE_DOC, (match, id) => {
    return `ChurchOperationalPaths.churchDoc(${id})`;
  });

  if (content !== original) {
    content = addImport(content);
    fs.writeFileSync(filePath, content, 'utf8');
    return true;
  }
  return false;
}

const files = walk(ROOT);
const migrated = [];
for (const f of files) {
  if (migrateFile(f)) migrated.push(path.relative(ROOT, f).replace(/\\/g, '/'));
}
console.log(`Migrated ${migrated.length} files:`);
migrated.forEach((f) => console.log('  ' + f));
