// Types mirroring the engine's data/inventory.json schema (see engine/lib/Export-Inventory.ps1).

export interface InventoryMeta {
  tool: string;
  phase: number;
  engineVersion: string;
  generatedUtc: string;
  target: {
    tenantId: string;
    subscriptionId: string;
    resourceGroupName?: string | null;
    storageAccount: string;
    fileSystem: string;
    rootPath: string;
  };
  auth: { mode: string; account?: string | null };
  counts: Record<string, number>;
  notes: string[];
}

export interface Folder {
  id: string;
  path: string;
  name: string;
  depth: number;
  isDirectory: boolean;
  level1?: string | null;
  level2?: string | null;
  level3?: string | null;
  level4?: string | null;
  owner?: string;
  ownerGroup?: string;
  basePermissions?: string;
}

export interface Group {
  id: string;
  displayName: string;
  description?: string | null;
  kind: string;
  role?: string;
  status?: string;
  onAce?: boolean;
  memberCount?: number;
  totalNestedGroups?: number;
  effectiveUserCount?: number;
  reachable?: boolean;
  securityEnabled: boolean;
  mail?: string | null;
}

export interface User {
  id: string;
  upn: string;
  displayName: string;
  jobTitle?: string | null;
  accountEnabled: boolean;
  directGroupCount?: number;
  effectiveGroupCount?: number;
}

export interface Membership { groupId: string; memberId: string; memberType: string }
export interface Nesting { parentGroupId: string; childGroupId: string }
export interface Rbac { principalId: string; principalType: string; roleDefinitionName: string; scope: string }
export interface OrphanGroup { id: string; displayName: string; emptyMembers: boolean; notOnAnyAce: boolean; status?: string }

export interface Inventory {
  meta: InventoryMeta;
  folders: Folder[];
  groups: Group[];
  users: User[];
  memberships: Membership[];
  groupNesting: Nesting[];
  rbacAssignments: Rbac[];
  hygiene: { orphanGroups: OrphanGroup[]; staleUsers: User[] };
  aceJsonl?: string;
}

// --- Tab 2 (legacy JSON path): AI proposition (mirrors ai/recommendations.schema.json) ---
export interface RecRole {
  id: string;
  displayName: string;
  scope: string;
  accessLevel: string;
  azureRole: string;
  folderScope: string;
  replacesGroupCount: number;
  replacesGroupsSample?: string[];
  suggestedMembers?: string[];
  rationale: string;
  confidence: string;
  decision?: string;
}
export interface RecFinding { id: string; severity: string; title: string; detail: string }
export interface Recommendations {
  meta: { tool: string; phase: number; generatedUtc: string; source: string; author?: string; notes?: string[] };
  summary: { currentGroups: number; proposedRoleCount: number; groupsEliminated: number; reductionPct: number; headline?: string };
  roles: RecRole[];
  findings?: RecFinding[];
}

// --- Tab 2: deterministic proposition, read from aclassist.db (engine/sql/propose.sql) ---
export interface ProposalSummary {
  scanId: string;
  generatedUtc: string;
  currentGroups: number;
  proposedRoleCount: number;
  retireDormant: number;
  retireUnused: number;
  mergeDuplicate: number;
  flattenNesting: number;
  mapToRole: number;
  keepGroup: number;
  usersOverThreshold: number;
  rolesNeedingReview: number;
  safeRemovable: number;
  groupsAfterSafe: number;
  groupsAfterFull: number;
  safeReductionPct: number;
  fullReductionPct: number;
}

export interface ProposedRole {
  roleId: string;
  baseDir: string;
  accessLevel: string;
  azureRole: string;
  folderScope: string;
  replacesGroupCount: number;
  memberUserCount: number;
  coveredFolderCount: number;
  scopeFolderCount: number;
  /** Folders the role would expose that the groups it replaces did not already grant. */
  newFolderCount: number;
  accessSafe: boolean;
  displayName: string;
  rationale: string;
  confidence: string;
  /** 'deterministic' or 'ai' — the AI may only ever change displayName / rationale. */
  namedBy: string;
  decision: string;
}

export interface ProposedGroupAction {
  groupId: string;
  displayName: string;
  observedRole: string;
  status: string;
  memberCount: number;
  effectiveUserCount: number;
  action: string;
  target: string;
  reason: string;
  accessSafe: boolean;
  decision: string;
}

export interface ProposedUserFlag {
  userId: string;
  upn: string;
  displayName: string;
  jobTitle: string;
  directGroupCount: number;
  effectiveGroupCount: number;
  threshold: number;
  overThreshold: boolean;
}

export interface Proposal {
  summary: ProposalSummary;
  roles: ProposedRole[];
  actions: ProposedGroupAction[];
  userFlags: ProposedUserFlag[];
}
