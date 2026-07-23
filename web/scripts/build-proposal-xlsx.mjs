// Builds data/proposed-model.xlsx (editable, with a Decision column) from data/recommendations.json.
// Deterministic — no AI, no Azure. Reuses write-excel-file (MIT). The AI writes the JSON; this writes the sheet.
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import writeXlsxFile from 'write-excel-file/node';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '../..');
const recPath = resolve(repoRoot, 'data/recommendations.json');
const outPath = resolve(repoRoot, 'data/proposed-model.xlsx');

if (!existsSync(recPath)) {
  console.error(`[build-proposal] ${recPath} not found.\n  Run the assessment prompt (ai/prompts/assess.prompt.md) in Copilot first to produce it.`);
  process.exit(1);
}

const rec = JSON.parse(readFileSync(recPath, 'utf8'));
const roles = Array.isArray(rec.roles) ? rec.roles : [];
if (roles.length === 0) {
  console.error('[build-proposal] recommendations.json has no roles[]. Nothing to write.');
  process.exit(1);
}

const columns = [
  { header: 'Decision', width: 14, cell: (r) => r.decision || '' },
  { header: 'Role ID', width: 26, cell: (r) => r.id || '' },
  { header: 'Display name', width: 26, cell: (r) => r.displayName || '' },
  { header: 'Scope', cell: (r) => r.scope || '' },
  { header: 'Access level', cell: (r) => r.accessLevel || '' },
  { header: 'Azure role (suggested)', width: 30, cell: (r) => r.azureRole || '' },
  { header: 'Replaces (# groups)', cell: (r) => (typeof r.replacesGroupCount === 'number' ? r.replacesGroupCount : 0) },
  { header: 'Folder scope', cell: (r) => r.folderScope || '' },
  { header: 'Confidence', cell: (r) => r.confidence || '' },
  { header: 'Suggested members', width: 32, cell: (r) => (Array.isArray(r.suggestedMembers) ? r.suggestedMembers.join(', ') : '') },
  { header: 'Rationale', width: 60, cell: (r) => r.rationale || '' },
  { header: 'Reviewer notes', width: 30, cell: () => '' },
];

mkdirSync(dirname(outPath), { recursive: true });
await writeXlsxFile(roles, {
  columns,
  headerStyle: { fontWeight: 'bold' },
}).toFile(outPath);

const decided = roles.filter((r) => r.decision).length;
console.log(`[build-proposal] wrote ${outPath}`);
console.log(`  ${roles.length} proposed roles (${decided} with a decision set). Open in Excel and set Decision = Approve / Modify / Reject.`);
