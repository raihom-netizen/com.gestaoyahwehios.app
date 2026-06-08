#!/usr/bin/env node
/** Remove referências Firestore órfãs antes de ChurchOperationalPaths.churchDoc */
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(import.meta.dirname, '..', 'flutter_app', 'lib');

const ORPHAN_RE =
  /(?:FirebaseFirestore\.instance|firebaseDefaultFirestore|_db|_fs|db|firestore)\s*\n(\s*)ChurchOperationalPaths\.churchDoc/g;

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
  let c = fs.readFileSync(f, 'utf8');
  const orig = c;
  c = c.replace(ORPHAN_RE, '$1ChurchOperationalPaths.churchDoc');
  // Also inline: db ChurchOperationalPaths (no dot)
  c = c.replace(
    /(?:FirebaseFirestore\.instance|firebaseDefaultFirestore|_db|_fs|db|firestore)\s+ChurchOperationalPaths\.churchDoc/g,
    'ChurchOperationalPaths.churchDoc',
  );
  if (c !== orig) {
    fs.writeFileSync(f, c, 'utf8');
    fixed++;
    console.log(path.relative(ROOT, f).replace(/\\/g, '/'));
  }
}
console.log(`Fixed ${fixed} files`);
