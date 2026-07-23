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

// --- Tab 2: AI proposition (mirrors ai/recommendations.schema.json) ---
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
