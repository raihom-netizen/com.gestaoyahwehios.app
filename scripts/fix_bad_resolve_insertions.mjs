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

const RESOLVE =
  /final op = await ChurchOperationalPaths\.resolveCached\(([^)]+)\);/;

let fixed = 0;
for (const f of walk(ROOT)) {
  let lines = fs.readFileSync(f, 'utf8').split('\n');
  let changed = false;

  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(RESOLVE);
    if (!m) continue;

    const prev = i > 0 ? lines[i - 1].trimEnd() : '';
    const badContext =
      prev.endsWith('(') ||
      prev.endsWith('=') ||
      prev.endsWith('=>') ||
      prev.endsWith('add(') ||
      prev.endsWith('wait(') ||
      prev.endsWith('map(') ||
      prev.endsWith('getDocument(') ||
      prev.endsWith('getQuery(') ||
      /CollectionReference|DocumentReference/.test(prev);

    if (!badContext) continue;

    const resolveLine = lines[i].trim();
    const seed = m[1];
    lines.splice(i, 1);
    changed = true;

    // hoist: encontrar início do statement (linha com ; ou { acima)
    let stmtStart = i - 1;
    while (stmtStart > 0) {
      const t = lines[stmtStart].trim();
      if (t.endsWith('{') || t.endsWith(';')) break;
      if (/^\s*(try|catch|finally|else|if|for|while|await|final|var|return)\b/.test(lines[stmtStart])) break;
      stmtStart--;
    }
    const indent = lines[stmtStart + 1]?.match(/^(\s*)/)?.[1] ?? '    ';
    lines.splice(stmtStart + 1, 0, `${indent}${resolveLine}`);

    // fix sync getter: remove resolve if => on prev after splice
    i = stmtStart;
  }

  // sync getters com await — remover resolve e usar param
  for (let i = 0; i < lines.length; i++) {
    if (!RESOLVE.test(lines[i])) continue;
    const prev = i > 0 ? lines[i - 1] : '';
    if (!prev.trimEnd().endsWith('=>')) continue;
    const paramMatch = prev.match(/\((\w+)/);
    const param = paramMatch ? paramMatch[1] : 'tenantId';
    lines.splice(i, 1);
    for (let j = i; j < Math.min(i + 5, lines.length); j++) {
      lines[j] = lines[j].replace(/churchDoc\(op\)/, `churchDoc(${param}.trim())`);
    }
    changed = true;
  }

  if (changed) {
    fs.writeFileSync(f, lines.join('\n'), 'utf8');
    fixed++;
    console.log(path.relative(ROOT, f).replace(/\\/g, '/'));
  }
}

console.log(`Repaired ${fixed} files`);
