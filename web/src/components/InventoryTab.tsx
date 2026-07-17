import { useMemo, useState } from 'react';
import type { Inventory, Group, Folder, User, Rbac, OrphanGroup } from '../types';
import { KpiCards } from './KpiCards';
import { DataTable, type Column } from './DataTable';

type Sub = 'groups' | 'folders' | 'users' | 'rbac';

export function InventoryTab({ inv }: { inv: Inventory }) {
  const [sub, setSub] = useState<Sub>('groups');
  const orphanById = useMemo(
    () => new Map<string, OrphanGroup>(inv.hygiene.orphanGroups.map((o) => [o.id, o])),
    [inv],
  );

  const subs: { key: Sub; label: string; count: number }[] = [
    { key: 'groups', label: 'Groups', count: inv.groups.length },
    { key: 'folders', label: 'Folders', count: inv.folders.length },
    { key: 'users', label: 'Users', count: inv.users.length },
    { key: 'rbac', label: 'RBAC', count: inv.rbacAssignments.length },
  ];

  return (
    <div className="tabpanel">
      <KpiCards inv={inv} />

      <div className="callout">
        <span className="callout-icon">◆</span>
        <div>
          <b>Sprawl signal — {(inv.meta.counts.orphanGroups ?? 0).toLocaleString()} of {(inv.meta.counts.groups ?? 0).toLocaleString()} groups are orphaned</b>
          <div className="callout-sub">Groups with no members and/or not used on any folder ACL — the prime consolidation candidates the AI proposition (Tab 2) will target.</div>
        </div>
      </div>

      <div className="subtabs">
        {subs.map((s) => (
          <button key={s.key} className={sub === s.key ? 'subtab active' : 'subtab'} onClick={() => setSub(s.key)}>
            {s.label} <span className="subtab-count">{s.count.toLocaleString()}</span>
          </button>
        ))}
      </div>

      {sub === 'groups' && <GroupsTable groups={inv.groups} orphanById={orphanById} />}
      {sub === 'folders' && <FoldersTable folders={inv.folders} />}
      {sub === 'users' && <UsersTable users={inv.users} />}
      {sub === 'rbac' && <RbacTable rbac={inv.rbacAssignments} />}
    </div>
  );
}

function GroupsTable({ groups, orphanById }: { groups: Group[]; orphanById: Map<string, OrphanGroup> }) {
  const columns: Column<Group>[] = [
    { key: 'displayName', header: 'Group', render: (g) => <span className="mono">{g.displayName}</span> },
    { key: 'kind', header: 'Kind', render: (g) => <span className={'tag tag-' + g.kind.toLowerCase()}>{g.kind}</span> },
    {
      key: 'status', header: 'Status', render: (g) => {
        const o = orphanById.get(g.id);
        if (!o) return <span className="tag tag-ok">in use</span>;
        const parts = [o.emptyMembers ? 'no members' : null, o.notOnAnyAce ? 'no ACL' : null].filter(Boolean).join(' · ');
        return <span className="tag tag-warn">orphan ({parts})</span>;
      },
    },
    { key: 'id', header: 'Object ID', render: (g) => <span className="mono dim">{g.id}</span> },
  ];
  return <DataTable rows={groups} columns={columns} searchText={(g) => `${g.displayName} ${g.kind} ${g.id}`} />;
}

function FoldersTable({ folders }: { folders: Folder[] }) {
  const columns: Column<Folder>[] = [
    { key: 'path', header: 'Path', render: (f) => <span className="mono">{f.path}</span> },
    { key: 'depth', header: 'Depth', value: (f) => f.depth },
    { key: 'level1', header: 'Dept', value: (f) => f.level1 ?? '' },
    { key: 'level3', header: 'Layer', value: (f) => f.level3 ?? '' },
    { key: 'basePermissions', header: 'Base perms', render: (f) => <span className="mono">{f.basePermissions}</span> },
  ];
  return <DataTable rows={folders} columns={columns} searchText={(f) => f.path} />;
}

function UsersTable({ users }: { users: User[] }) {
  const columns: Column<User>[] = [
    { key: 'displayName', header: 'Name', value: (u) => u.displayName },
    { key: 'upn', header: 'UPN', render: (u) => <span className="mono">{u.upn}</span> },
    { key: 'jobTitle', header: 'Job title', value: (u) => u.jobTitle ?? '' },
    { key: 'accountEnabled', header: 'Enabled', render: (u) => <span className={'tag ' + (u.accountEnabled ? 'tag-ok' : 'tag-warn')}>{u.accountEnabled ? 'yes' : 'no'}</span> },
  ];
  return <DataTable rows={users} columns={columns} searchText={(u) => `${u.displayName} ${u.upn} ${u.jobTitle ?? ''}`} />;
}

function RbacTable({ rbac }: { rbac: Rbac[] }) {
  const columns: Column<Rbac>[] = [
    { key: 'roleDefinitionName', header: 'Role', render: (r) => <span className="tag tag-adls">{r.roleDefinitionName}</span> },
    { key: 'principalType', header: 'Principal type', value: (r) => r.principalType },
    { key: 'principalId', header: 'Principal', render: (r) => <span className="mono dim">{r.principalId}</span> },
    { key: 'scope', header: 'Scope', render: (r) => <span className="mono dim">{r.scope.split('/').slice(-2).join('/')}</span> },
  ];
  return <DataTable rows={rbac} columns={columns} searchText={(r) => `${r.roleDefinitionName} ${r.principalType} ${r.scope}`} />;
}
