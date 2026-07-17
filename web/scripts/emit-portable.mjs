// Copies the single-file build (dist/index.html) to a committed, ready-to-open artifact:
//   dashboard/ACLassist.html — the customer opens it in any browser. No install, no server.
import { copyFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, '../dist/index.html');
const outDir = resolve(here, '../../dashboard');
mkdirSync(outDir, { recursive: true });
const dest = resolve(outDir, 'ACLassist.html');
copyFileSync(src, dest);
const kb = (statSync(dest).size / 1024).toFixed(0);
console.log(`[portable] wrote dashboard/ACLassist.html (${kb} KB) — open it in any browser, no install needed.`);
