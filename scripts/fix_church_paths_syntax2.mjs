#!/usr/bin/env node
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(import.meta.dirname, '..', 'flutter_app', 'lib');

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, out);
    else if (ent.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

// FirebaseFirestore\n.instance\nChurchOperationalPaths
const SPLIT_INSTANCE =
  /FirebaseFirestore\s*\n\s*\.instance\s*\n(\s*)ChurchOperationalPaths\.churchDoc/g;

// prefix\nChurchOperationalPaths (dbRetry, await db, etc.)
const PREFIX_BEFORE_DOC =
  /(?:await\s+)?(?:dbRetry|db|_db|fs|firestore)\s*\n(\s*)ChurchOperationalPaths\.churchDoc/g;

// Broken import: line without semicolon before church_operational_paths import
function fixBrokenImports(c) {
  return c.replace(
    /(import 'package:[^']+')\n(import 'package:gestao_yahweh\/services\/church_operational_paths\.dart';)\n(\s*show\s+)/g,
    "$1;\n$2\n$3",
  ).replace(
    /(import 'package:[^']+)'\n(import 'package:gestao_yahweh\/services\/church_operational_paths\.dart';)\n(\s*show\s+)/g,
    "$1';\n$2\n$3",
  );
}

let fixed = 0;
for (const f of walk(ROOT)) {
  let c = fs.readFileSync(f, 'utf8');
  const orig = c;
  c = c.replace(SPLIT_INSTANCE, '$1ChurchOperationalPaths.churchDoc');
  c = c.replace(PREFIX_BEFORE_DOC, '$1ChurchOperationalPaths.churchDoc');
  c = fixBrokenImports(c);
  if (c !== orig) {
    fs.writeFileSync(f, c, 'utf8');
    fixed++;
    console.log(path.relative(ROOT, f).replace(/\\/g, '/'));
  }
}
console.log(`Fixed ${fixed} files`);
