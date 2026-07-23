// Copies a real scan output (../data/inventory.json[.jsonl]) into web/public so the dashboard serves it.
// If no scan output exists, leaves any existing sample in place. Never touches Azure.
import { existsSync, copyFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const publicDir = resolve(here, '../public');
mkdirSync(publicDir, { recursive: true });

let copied = 0;
for (const name of ['inventory.json', 'inventory.jsonl', 'recommendations.json']) {
  const src = resolve(here, '../../data', name);
  if (existsSync(src)) {
    copyFileSync(src, resolve(publicDir, name));
    console.log(`[sync-data] copied ../data/${name} -> public/${name}`);
    copied++;
  }
}
if (copied === 0) {
  console.log('[sync-data] no ../data/inventory.json found; using existing public/ sample (run "npm run generate-sample" for demo data).');
}
