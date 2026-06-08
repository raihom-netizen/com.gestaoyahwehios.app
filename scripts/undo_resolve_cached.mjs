#!/usr/bin/env node
/** Desfaz inserções do add_resolve_cached — mantém churchDoc */
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(import.meta.dirname, '..', 'flutter_app', 'lib');
const LINE_RE =
  /^(\s*)final op = await ChurchOperationalPaths\.resolveCached\((.+)\);\s*$/;

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, out);
    else if (ent.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

let n = 0;
for (const f of walk(ROOT)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  const seeds = [];
  const out = [];
  for (const line of lines) {
    const m = line.match(LINE_RE);
    if (m) {
      seeds.push(m[2].trim());
      n++;
      continue;
    }
    out.push(line);
  }
  if (seeds.length === 0) continue;
  let content = out.join('\n');
  // substituir churchDoc(op) pelo último seed conhecido (heurística LIFO por bloco)
  let si = 0;
  content = content.replace(/ChurchOperationalPaths\.churchDoc\(op\)/g, () => {
    const seed = seeds[Math.min(si, seeds.length - 1)];
    si++;
    return `ChurchOperationalPaths.churchDoc(${seed})`;
  });
  fs.writeFileSync(f, content, 'utf8');
  console.log(path.relative(ROOT, f).replace(/\\/g, '/'));
}
console.log(`Removed ${n} resolveCached lines`);
