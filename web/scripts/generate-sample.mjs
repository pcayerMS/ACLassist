// Portable DEMO-DATA generator for the ACLassist dashboard.
// Produces web/public/inventory.json (+ inventory.jsonl) with a realistic ADLS ACL sprawl that mirrors
// the shape the engine emits. Purely synthetic — no real data and no Azure access.
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const publicDir = resolve(here, '../public');
mkdirSync(publicDir, { recursive: true });

const areasByDept = {
  Commercial: ['Sales', 'Marketing', 'Loyalty', 'Pricing'],
  DataScience: ['Modeling', 'Features', 'Experiments', 'Datasets'],
  Finance: ['Budget', 'Forecast', 'Payroll', 'Tax'],
  HR: ['Recruiting', 'Payroll', 'Benefits', 'Training'],
  IT: ['Infra', 'Security', 'DevOps', 'Support'],
  Operations: ['Crew', 'Maintenance', 'Scheduling', 'Cargo'],
};
const depts = Object.keys(areasByDept);
const layers = ['Bronze', 'Silver', 'Gold'];
const projects = ['Project001', 'Project002', 'Project003', 'Project004'];
const variants = ['R', 'W', 'X', 'RW', 'RX', 'WX', 'RWX', 'D_X'];
const variantPerm = { R: 'r-x', W: '-w-', X: '--x', RW: 'rw-', RX: 'r-x', WX: '-wx', RWX: 'rwx', D_X: '--x' };

const folders = [];
const groups = [];
const groupId = new Map();
const aces = [];

function addFolder(path, l1, l2, l3, l4) {
  folders.push({
    id: path, path, name: path === '/' ? '/' : path.split('/').pop(),
    depth: path === '/' ? 0 : path.replace(/^\//, '').split('/').length,
    isDirectory: true, level1: l1 ?? null, level2: l2 ?? null, level3: l3 ?? null, level4: l4 ?? null,
    owner: 'superuser', ownerGroup: 'supergroup', basePermissions: 'rwxr-x---',
  });
  aces.push({ folderPath: path, principalId: '', principalType: 'user', scope: 'access', permissions: 'rwx', isNamed: false });
  aces.push({ folderPath: path, principalId: '', principalType: 'group', scope: 'access', permissions: 'r-x', isNamed: false });
  aces.push({ folderPath: path, principalId: '', principalType: 'mask', scope: 'access', permissions: 'rwx', isNamed: false });
  aces.push({ folderPath: path, principalId: '', principalType: 'other', scope: 'access', permissions: '---', isNamed: false });
}
function ensureGroup(name, kind) {
  if (groupId.has(name)) return groupId.get(name);
  const id = randomUUID();
  groupId.set(name, id);
  groups.push({ id, displayName: name, description: 'LAB1', kind, securityEnabled: true, mail: null });
  return id;
}

addFolder('/', null, null, null, null);
const guestId = randomUUID();
aces.push({ folderPath: '/', principalId: guestId, principalType: 'user', scope: 'access', permissions: '--x', isNamed: true });

const prdGroups = ['PRD_Finance_Reporting', 'PRD_Loyalty_Reporting', 'PRD_FlightOps_Analytics', 'PRD_Analytics_Platform', 'PRD_Data_Ingestion', 'PRD_HR_People', 'PRD_IT_Platform', 'PRD_Commercial_Insights'];
for (const p of prdGroups) ensureGroup(p, 'PRD');

for (const dept of depts) {
  addFolder(`/${dept}`, dept);
  for (const area of areasByDept[dept]) {
    addFolder(`/${dept}/${area}`, dept, area);
    for (const layer of layers) {
      addFolder(`/${dept}/${area}/${layer}`, dept, area, layer);
      for (const project of projects) {
        const path = `/${dept}/${area}/${layer}/${project}`;
        addFolder(path, dept, area, layer, project);
        for (const v of variants) {
          const gid = ensureGroup(`ADLS_${dept}_${area}_${layer}_${project}_${v}`, 'ADLS');
          aces.push({ folderPath: path, principalId: gid, principalType: 'group', scope: v === 'D_X' ? 'default' : 'access', permissions: variantPerm[v], isNamed: true });
        }
      }
    }
  }
}

const firstNames = ['Alex', 'Sophie', 'Marc', 'Julie', 'Nadia', 'Liam', 'Emma', 'Noah', 'Olivia', 'Lucas', 'Mia', 'Ethan', 'Ava', 'Leo', 'Zoe', 'Sam', 'Ana', 'Ravi', 'Wei', 'Ingrid'];
const lastNames = ['Tremblay', 'Gagnon', 'Roy', 'Cote', 'Bouchard', 'Smith', 'Brown', 'Nguyen', 'Patel', 'Garcia', 'Muller', 'Rossi', 'Kim', 'Lopez', 'Singh', 'Chen', 'Dubois', 'Silva', 'Haddad', 'Novak'];
const jobRoles = ['Business Analyst', 'Data Analyst', 'Data Engineer', 'Data Scientist', 'Platform Engineer', 'Finance Analyst', 'HR Specialist', 'Ops Analyst'];
const users = [];
const memberships = [];
for (let i = 0; i < 50; i++) {
  const fn = firstNames[i % firstNames.length];
  const ln = lastNames[(i * 3) % lastNames.length];
  const id = randomUUID();
  users.push({ id, upn: `${fn.toLowerCase()}.${ln.toLowerCase()}${i}@lab.contoso.com`, displayName: `${fn} ${ln}`, jobTitle: jobRoles[i % jobRoles.length], accountEnabled: true });
  memberships.push({ groupId: groupId.get(prdGroups[i % prdGroups.length]), memberId: id, memberType: 'user' });
  if (i % 3 === 0) memberships.push({ groupId: groupId.get(prdGroups[(i + 2) % prdGroups.length]), memberId: id, memberType: 'user' });
}
users.push({ id: guestId, upn: 'patrickcayer_microsoft.com#EXT#@lab.contoso.com', displayName: 'Patrick Cayer (guest)', jobTitle: 'Finance Analyst', accountEnabled: true });
memberships.push({ groupId: groupId.get('PRD_Finance_Reporting'), memberId: guestId, memberType: 'user' });

const adlsNames = [...groupId.keys()].filter(n => n.startsWith('ADLS_'));
const nesting = [];
let ni = 0;
for (const prd of prdGroups) {
  const prdId = groupId.get(prd);
  for (let k = 0; k < 24; k++, ni += 13) nesting.push({ parentGroupId: prdId, childGroupId: groupId.get(adlsNames[ni % adlsNames.length]) });
}

// a handful of users have direct ADLS group exceptions, so ~18 ADLS groups are NOT orphaned
for (let i = 0; i < 18; i++) {
  memberships.push({ groupId: groupId.get(adlsNames[(i * 97) % adlsNames.length]), memberId: users[i % users.length].id, memberType: 'user' });
}

const roleNames = ['Owner', 'Contributor', 'Reader', 'Storage Blob Data Owner', 'Storage Blob Data Reader', 'Storage Blob Data Contributor'];
const rbacAssignments = [];
for (let i = 0; i < 10; i++) rbacAssignments.push({ principalId: randomUUID(), principalType: i % 2 ? 'User' : 'Group', roleDefinitionName: roleNames[i % roleNames.length], scope: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg/providers/Microsoft.Storage/storageAccounts/stcontosodemo' });

const referenced = new Set(aces.filter(a => a.isNamed && a.principalType === 'group').map(a => a.principalId));
const memberCountMap = new Map();
for (const m of memberships) memberCountMap.set(m.groupId, (memberCountMap.get(m.groupId) || 0) + 1);
const isParent = new Set(nesting.map(n => n.parentGroupId));

// transitive reachability: does >=1 USER end up an effective member? (members flow child -> parent)
const directUsers = new Set(memberships.filter(m => m.memberType === 'user').map(m => m.groupId));
const childrenOf = new Map();
for (const m of memberships) if (m.memberType === 'group') { if (!childrenOf.has(m.groupId)) childrenOf.set(m.groupId, []); childrenOf.get(m.groupId).push(m.memberId); }
for (const n of nesting) { if (!childrenOf.has(n.parentGroupId)) childrenOf.set(n.parentGroupId, []); childrenOf.get(n.parentGroupId).push(n.childGroupId); }
const reachMemo = new Map();
function isReachable(gid, stack) {
  if (reachMemo.has(gid)) return reachMemo.get(gid);
  if (stack.has(gid)) return false;
  let r = false;
  if (directUsers.has(gid)) r = true;
  else if (childrenOf.has(gid)) { stack.add(gid); for (const c of childrenOf.get(gid)) { if (isReachable(c, stack)) { r = true; break; } } stack.delete(gid); }
  reachMemo.set(gid, r);
  return r;
}

for (const g of groups) {
  const onAce = referenced.has(g.id);
  const mc = memberCountMap.get(g.id) || 0;
  const hasMem = mc > 0 || isParent.has(g.id);
  const reachable = isReachable(g.id, new Set());
  const role = onAce && hasMem ? 'hybrid' : onAce ? 'access' : hasMem ? 'role' : 'unused';
  const status = role === 'unused' ? 'unused' : (onAce && !reachable ? 'unreachable' : 'active');
  g.role = role; g.status = status; g.onAce = onAce; g.memberCount = mc; g.reachable = reachable;
}
const orphanGroups = groups.filter(g => g.status !== 'active')
  .map(g => ({ id: g.id, displayName: g.displayName, emptyMembers: !(g.memberCount > 0 || isParent.has(g.id)), notOnAnyAce: !g.onAce, status: g.status }));
const nAccessGroups = groups.filter(g => g.role === 'access' || g.role === 'hybrid').length;
const nRoleGroups = groups.filter(g => g.role === 'role').length;
const nUnreachable = groups.filter(g => g.status === 'unreachable').length;

const inventory = {
  meta: {
    tool: 'adls-acl-assessment', phase: 1, engineVersion: '0.1.0-sample', generatedUtc: new Date().toISOString(),
    target: { tenantId: 'demo.onmicrosoft.com', subscriptionId: '00000000-0000-0000-0000-000000000000', resourceGroupName: 'demo-rg', storageAccount: 'stcontosodemo', fileSystem: 'demo-container', rootPath: '/' },
    auth: { mode: 'interactive', account: 'demo@contoso.com' },
    counts: { folders: folders.length, aces: aces.length, groups: groups.length, users: users.length, memberships: memberships.length, groupNesting: nesting.length, rbacAssignments: rbacAssignments.length, accessGroups: nAccessGroups, roleGroups: nRoleGroups, unreachableGroups: nUnreachable, orphanGroups: orphanGroups.length, staleUsers: 0 },
    notes: ['SAMPLE/DEMO data generated by scripts/generate-sample.mjs — not from a real scan.'],
  },
  folders, groups, users, memberships, groupNesting: nesting, rbacAssignments,
  hygiene: { orphanGroups, staleUsers: [] },
  aceJsonl: 'inventory.jsonl',
};

writeFileSync(resolve(publicDir, 'inventory.json'), JSON.stringify(inventory, null, 2));
writeFileSync(resolve(publicDir, 'inventory.jsonl'),
  aces.map(a => JSON.stringify({ folderId: a.folderPath, folderPath: a.folderPath, principalId: a.principalId, principalType: a.principalType, scope: a.scope, permissions: a.permissions, isNamed: a.isNamed })).join('\n') + '\n');
console.log(`[generate-sample] folders=${folders.length} groups=${groups.length} (access=${nAccessGroups} role=${nRoleGroups} unreachable=${nUnreachable}) users=${users.length} aces=${aces.length}`);
