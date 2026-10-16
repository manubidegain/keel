// Minimal lint: no console.log in src/, no `var`.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
let bad = 0;
function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.js')) {
      readFileSync(p, 'utf8').split('\n').forEach((l, i) => {
        if (/console\.log\(/.test(l)) { console.error(`${p}:${i + 1} console.log`); bad++; }
        if (/^\s*var\s/.test(l)) { console.error(`${p}:${i + 1} var`); bad++; }
      });
    }
  }
}
walk('src');
process.exit(bad ? 1 : 0);
