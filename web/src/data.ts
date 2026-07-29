import initSqlJs from 'sql.js';
import type { Database } from 'sql.js';
import wasmUrl from 'sql.js/dist/sql-wasm.wasm?url';
import type { Inventory, Proposal } from './types';

const base = import.meta.env.BASE_URL ?? '/';

export interface LoadResult {
  inventory: Inventory;
  /** null when the database has no proposition yet (engine/Invoke-Proposition.ps1 has not been run). */
  proposal: Proposal | null;
}

let sqlPromise: ReturnType<typeof initSqlJs> | null = null;
function getSql() {
  if (!sqlPromise) sqlPromise = initSqlJs({ locateFile: () => wasmUrl });
  return sqlPromise;
}

function rows(db: Database, sql: string): Record<string, unknown>[] {
  const res = db.exec(sql);
  if (!res.length) return [];
  const { columns, values } = res[0];
  return values.map((v) => { const o: Record<string, unknown> = {}; columns.forEach((c, i) => { o[c] = v[i]; }); return o; });
}
function scalar(db: Database, sql: string): number {
  const r = db.exec(sql);
  return r.length && r[0].values.length ? Number(r[0].values[0][0]) : 0;
}
function hasTable(db: Database, name: string): boolean {
  const r = db.exec(`SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='${name}'`);
  return !!(r.length && Number(r[0].values[0][0]) > 0);
}
const S = (v: unknown) => (v === null || v === undefined ? '' : String(v));
const N = (v: unknown) => Number(v ?? 0);
const B = (v: unknown) => !!v && v !== 0 && v !== '0';

function buildInventory(db: Database): Inventory {
  const meta: Record<string, string> = {};
  for (const m of rows(db, 'SELECT key, value FROM meta')) meta[S(m.key)] = S(m.value);

  const groups = rows(db, `SELECT g.id, g.display_name, g.kind, g.security_enabled, g.mail,
      gm.member_count, gm.total_nested_groups, gm.effective_user_count, gm.on_ace, gm.role, gm.status
    FROM groups g JOIN group_metrics gm ON gm.group_id = g.id`).map((r) => ({
    id: S(r.id), displayName: S(r.display_name), kind: S(r.kind) || 'other',
    securityEnabled: B(r.security_enabled), mail: r.mail == null ? null : S(r.mail),
    memberCount: N(r.member_count), totalNestedGroups: N(r.total_nested_groups),
    effectiveUserCount: N(r.effective_user_count), onAce: B(r.on_ace),
    role: S(r.role), status: S(r.status),
  }));

  const users = rows(db, `SELECT u.id, u.upn, u.display_name, u.job_title, u.account_enabled,
      um.direct_group_count, um.effective_group_count
    FROM users u JOIN user_metrics um ON um.user_id = u.id`).map((r) => ({
    id: S(r.id), upn: S(r.upn), displayName: S(r.display_name),
    jobTitle: r.job_title == null ? null : S(r.job_title), accountEnabled: B(r.account_enabled),
    directGroupCount: N(r.direct_group_count), effectiveGroupCount: N(r.effective_group_count),
  }));

  const folders = rows(db, 'SELECT id, path, name, depth, level1, level2, level3, level4, base_permissions FROM folders').map((r) => ({
    id: S(r.id), path: S(r.path), name: S(r.name), depth: N(r.depth), isDirectory: true,
    level1: r.level1 == null ? null : S(r.level1), level2: r.level2 == null ? null : S(r.level2),
    level3: r.level3 == null ? null : S(r.level3), level4: r.level4 == null ? null : S(r.level4),
    basePermissions: S(r.base_permissions),
  }));

  const memberships = rows(db, 'SELECT group_id, member_id, member_type FROM memberships').map((r) => ({ groupId: S(r.group_id), memberId: S(r.member_id), memberType: S(r.member_type) }));
  const groupNesting = rows(db, 'SELECT parent_group_id, child_group_id FROM nesting').map((r) => ({ parentGroupId: S(r.parent_group_id), childGroupId: S(r.child_group_id) }));
  const rbacAssignments = rows(db, 'SELECT principal_id, principal_type, role_definition_name, scope FROM rbac').map((r) => ({ principalId: S(r.principal_id), principalType: S(r.principal_type), roleDefinitionName: S(r.role_definition_name), scope: S(r.scope) }));

  const snap = (rows(db, 'SELECT * FROM snapshots ORDER BY rowid DESC LIMIT 1')[0]) ?? {};
  const orphanGroups = groups.filter((g) => g.status !== 'active').map((g) => ({ id: g.id, displayName: g.displayName, emptyMembers: g.memberCount === 0, notOnAnyAce: !g.onAce, status: g.status }));

  const counts: Record<string, number> = {
    folders: folders.length, aces: scalar(db, 'SELECT COUNT(*) FROM aces'),
    groups: groups.length, users: users.length, memberships: memberships.length,
    groupNesting: groupNesting.length, rbacAssignments: rbacAssignments.length,
    accessGroups: N(snap.access_groups), roleGroups: N(snap.role_groups), dormantGroups: N(snap.dormant_groups),
    orphanGroups: orphanGroups.length,
    maxGroupsPerUser: N(snap.max_groups_per_user),
  };

  const isSample = (meta.tool || '').indexOf('sample') >= 0;
  return {
    meta: {
      tool: meta.tool || 'aclassist', phase: 1, engineVersion: meta.engineVersion || 'v2',
      generatedUtc: meta.generatedUtc || new Date().toISOString(),
      target: { tenantId: meta.tenantId || '', subscriptionId: meta.subscriptionId || '', resourceGroupName: null, storageAccount: meta.storageAccount || '', fileSystem: meta.fileSystem || '', rootPath: meta.rootPath || '/' },
      auth: { mode: 'interactive', account: meta.account || null },
      counts,
      notes: isSample ? ['SAMPLE/DEMO data — not from a real scan.'] : [],
    },
    folders, groups, users, memberships, groupNesting, rbacAssignments,
    hygiene: { orphanGroups, staleUsers: [] },
  } as Inventory;
}

/** Read the deterministic proposition, if engine/Invoke-Proposition.ps1 has written one into this database. */
function buildProposal(db: Database): Proposal | null {
  if (!hasTable(db, 'proposal_summary') || !hasTable(db, 'proposed_roles')) return null;
  const sRow = rows(db, 'SELECT * FROM proposal_summary LIMIT 1')[0];
  if (!sRow) return null;

  const summary = {
    scanId: S(sRow.scan_id), generatedUtc: S(sRow.generated_utc),
    currentGroups: N(sRow.current_groups), proposedRoleCount: N(sRow.proposed_role_count),
    retireDormant: N(sRow.retire_dormant), retireUnused: N(sRow.retire_unused),
    mergeDuplicate: N(sRow.merge_duplicate), flattenNesting: N(sRow.flatten_nesting),
    mapToRole: N(sRow.map_to_role), keepGroup: N(sRow.keep_group),
    usersOverThreshold: N(sRow.users_over_threshold), rolesNeedingReview: N(sRow.roles_needing_review),
    safeRemovable: N(sRow.safe_removable), groupsAfterSafe: N(sRow.groups_after_safe),
    groupsAfterFull: N(sRow.groups_after_full),
    safeReductionPct: N(sRow.safe_reduction_pct), fullReductionPct: N(sRow.full_reduction_pct),
  };

  const roles = rows(db, 'SELECT * FROM proposed_roles ORDER BY access_safe DESC, replaces_group_count DESC, role_id').map((r) => ({
    roleId: S(r.role_id), baseDir: S(r.base_dir), accessLevel: S(r.access_level),
    azureRole: S(r.azure_role), folderScope: S(r.folder_scope),
    replacesGroupCount: N(r.replaces_group_count), memberUserCount: N(r.member_user_count),
    coveredFolderCount: N(r.covered_folder_count), scopeFolderCount: N(r.scope_folder_count),
    newFolderCount: N(r.new_folder_count), accessSafe: B(r.access_safe),
    displayName: S(r.display_name), rationale: S(r.rationale), confidence: S(r.confidence),
    namedBy: S(r.named_by), decision: S(r.decision),
  }));

  const actions = rows(db, 'SELECT * FROM proposed_group_actions ORDER BY action, display_name').map((r) => ({
    groupId: S(r.group_id), displayName: S(r.display_name), observedRole: S(r.observed_role),
    status: S(r.status), memberCount: N(r.member_count), effectiveUserCount: N(r.effective_user_count),
    action: S(r.action), target: S(r.target), reason: S(r.reason), accessSafe: B(r.access_safe),
    decision: S(r.decision),
  }));

  const userFlags = hasTable(db, 'proposed_user_flags')
    ? rows(db, 'SELECT * FROM proposed_user_flags ORDER BY effective_group_count DESC, upn').map((r) => ({
      userId: S(r.user_id), upn: S(r.upn), displayName: S(r.display_name), jobTitle: S(r.job_title),
      directGroupCount: N(r.direct_group_count), effectiveGroupCount: N(r.effective_group_count),
      threshold: N(r.threshold), overThreshold: B(r.over_threshold),
    }))
    : [];

  return { summary, roles, actions, userFlags };
}

/** Open an aclassist.db and read both the inventory (Tab 1) and the proposition (Tab 2). */
export async function loadFromDb(bytes: Uint8Array): Promise<LoadResult> {
  const SQL = await getSql();
  const db = new SQL.Database(bytes);
  try {
    return { inventory: buildInventory(db), proposal: buildProposal(db) };
  } finally {
    db.close();
  }
}

export async function loadFromUrl(): Promise<LoadResult> {
  const res = await fetch(`${base}aclassist.db`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`could not load aclassist.db (HTTP ${res.status})`);
  return loadFromDb(new Uint8Array(await res.arrayBuffer()));
}
