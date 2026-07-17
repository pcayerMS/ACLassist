import { useMemo, useState } from 'react';
import type { Inventory, Group, Folder, User, Rbac, OrphanGroup } from '../types';
import { KpiCards, type KpiTarget } from './KpiCards';
import { DataTable, type Column } from './DataTable';

type Sub = 'groups' | 'folders' | 'users' | 'nesting' | 'memberships' | 'rbac';

export function InventoryTab({ inv }: { inv: Inventory }) {
  const [sub, setSub] = useState<Sub>('groups');
  const [pending, setPending] = useState<Record<string, string> | undefined>(undefined);

  const orphanById = useMemo(() => new Map<string, OrphanGroup>(inv.hygiene.orphanGroups.map((o) => [o.id, o])), [inv]);
  const groupName = useMemo(() => {
    const m = new Map(inv.groups.map((g) => [g.id, g.displayName]));
    return (id: string) => m.get(id) ?? id;
  }, [inv]);
  const userName = useMemo(() => {
    const m = new Map(inv.users.map((u) => [u.id, u.upn]));
    return (id: string) => m.get(id) ?? id;
  }, [inv]);

  function navigate(t: KpiTarget) {
    setSub(t.sub as Sub);
    setPending(t.filter ? { [t.filter.col]: t.filter.val } : {});
  }
  function pick(s: Sub) { setSub(s); setPending({}); }

  const subs: { key: Sub; label: string; count: number }[] = [
    { key: 'groups', label: 'Groups', count: inv.groups.length },
    { key: 'folders', label: 'Folders', count: inv.folders.length },
    { key: 'users', label: 'Users', count: inv.users.length },
    { key: 'nesting', label: 'Group nesting', count: inv.groupNesting.length },
    { key: 'memberships', label: 'Memberships', count: inv.memberships.length },
    { key: 'rbac', label: 'Storage roles', count: inv.rbacAssignments.length },
  ];

  return (
    <div className="tabpanel">
      <KpiCards inv={inv} onNavigate={navigate} />

      <div className="callout">
        <span className="callout-icon">◆</span>
        <div>
          <b>Sprawl signal — {(inv.meta.counts.orphanGroups ?? 0).toLocaleString()} of {(inv.meta.counts.groups ?? 0).toLocaleString()} groups are orphaned</b>
          <div className="callout-sub">Groups with no members and/or not used on any folder — the prime consolidation candidates the AI proposition (Tab 2) will target. Click any card above to jump to it.</div>
        </div>
      </div>

      <div className="subtabs">
        {subs.map((s) => (
          <button key={s.key} className={sub === s.key ? 'subtab active' : 'subtab'} onClick={() => pick(s.key)}>
            {s.label} <span className="subtab-count">{s.count.toLocaleString()}</span>
          </button>
        ))}
      </div>

      {sub === 'groups' && <GroupsTable groups={inv.groups} orphanById={orphanById} initial={pending} />}
      {sub === 'folders' && <FoldersTable folders={inv.folders} initial={pending} />}
      {sub === 'users' && <UsersTable users={inv.users} initial={pending} />}
      {sub === 'nesting' && <NestingTable inv={inv} groupName={groupName} initial={pending} />}
      {sub === 'memberships' && <MembershipsTable inv={inv} groupName={groupName} userName={userName} initial={pending} />}
      {sub === 'rbac' && <RbacTable rbac={inv.rbacAssignments} initial={pending} />}
    </div>
  );
}

function GroupsTable({ groups, orphanById, initial }: { groups: Group[]; orphanById: Map<string, OrphanGroup>; initial?: Record<string, string> }) {
  const columns: Column<Group>[] = [
    { key: 'displayName', header: 'Group', value: (g) => g.displayName, render: (g) => <span className="mono">{g.displayName}</span> },
    { key: 'kind', header: 'Kind', filter: 'select', value: (g) => g.kind, render: (g) => <span className={'tag tag-' + g.kind.toLowerCase()}>{g.kind}</span> },
    {
      key: 'status', header: 'Status', filter: 'select',
      value: (g) => (orphanById.has(g.id) ? 'orphan' : 'in use'),
      render: (g) => {
        const o = orphanById.get(g.id);
        if (!o) return <span className="tag tag-ok">in use</span>;
        const parts = [o.emptyMembers ? 'no members' : null, o.notOnAnyAce ? 'no ACL' : null].filter(Boolean).join(' · ');
        return <span className="tag tag-warn" title={parts}>orphan</span>;
      },
    },
    { key: 'id', header: 'Object ID', value: (g) => g.id, render: (g) => <span className="mono dim">{g.id}</span> },
  ];
  return <DataTable rows={groups} columns={columns} exportName="groups" initialFilters={initial} />;
}

function FoldersTable({ folders, initial }: { folders: Folder[]; initial?: Record<string, string> }) {
  const columns: Column<Folder>[] = [
    { key: 'path', header: 'Path', value: (f) => f.path, render: (f) => <span className="mono">{f.path}</span> },
    { key: 'depth', header: 'Depth', value: (f) => f.depth },
    { key: 'level1', header: 'Dept', filter: 'select', value: (f) => f.level1 ?? '' },
    { key: 'level3', header: 'Layer', filter: 'select', value: (f) => f.level3 ?? '' },
    { key: 'basePermissions', header: 'Base perms', value: (f) => f.basePermissions ?? '', render: (f) => <span className="mono">{f.basePermissions}</span> },
  ];
  return <DataTable rows={folders} columns={columns} exportName="folders" initialFilters={initial} />;
}

function UsersTable({ users, initial }: { users: User[]; initial?: Record<string, string> }) {
  const columns: Column<User>[] = [
    { key: 'displayName', header: 'Name', value: (u) => u.displayName },
    { key: 'upn', header: 'UPN', value: (u) => u.upn, render: (u) => <span className="mono">{u.upn}</span> },
    { key: 'jobTitle', header: 'Job title', filter: 'select', value: (u) => u.jobTitle ?? '' },
    { key: 'accountEnabled', header: 'Enabled', filter: 'select', value: (u) => (u.accountEnabled ? 'yes' : 'no'), render: (u) => <span className={'tag ' + (u.accountEnabled ? 'tag-ok' : 'tag-warn')}>{u.accountEnabled ? 'yes' : 'no'}</span> },
  ];
  return <DataTable rows={users} columns={columns} exportName="users" initialFilters={initial} />;
}

interface NestRow { parent: string; child: string }
function NestingTable({ inv, groupName, initial }: { inv: Inventory; groupName: (id: string) => string; initial?: Record<string, string> }) {
  const rows = useMemo<NestRow[]>(() => inv.groupNesting.map((n) => ({ parent: groupName(n.parentGroupId), child: groupName(n.childGroupId) })), [inv, groupName]);
  const columns: Column<NestRow>[] = [
    { key: 'parent', header: 'Parent group', value: (r) => r.parent, render: (r) => <span className="mono">{r.parent}</span> },
    { key: 'child', header: 'Member group (nested inside)', value: (r) => r.child, render: (r) => <span className="mono">{r.child}</span> },
  ];
  return (
    <>
      <div className="view-note">Which groups are nested inside which. The parent <b>contains</b> the member group, so the member's users inherit the parent's grants.</div>
      <DataTable rows={rows} columns={columns} exportName="group-nesting" initialFilters={initial} />
    </>
  );
}

interface MemRow { member: string; group: string; type: string }
function MembershipsTable({ inv, groupName, userName, initial }: { inv: Inventory; groupName: (id: string) => string; userName: (id: string) => string; initial?: Record<string, string> }) {
  const rows = useMemo<MemRow[]>(() => inv.memberships.map((m) => ({ member: m.memberType === 'user' ? userName(m.memberId) : groupName(m.memberId), group: groupName(m.groupId), type: m.memberType })), [inv, groupName, userName]);
  const columns: Column<MemRow>[] = [
    { key: 'member', header: 'Member', value: (r) => r.member, render: (r) => <span className="mono">{r.member}</span> },
    { key: 'group', header: 'Group', value: (r) => r.group, render: (r) => <span className="mono">{r.group}</span> },
    { key: 'type', header: 'Type', filter: 'select', value: (r) => r.type },
  ];
  return (
    <>
      <div className="view-note">Direct memberships — who belongs to which in-scope group.</div>
      <DataTable rows={rows} columns={columns} exportName="memberships" initialFilters={initial} />
    </>
  );
}

function RbacTable({ rbac, initial }: { rbac: Rbac[]; initial?: Record<string, string> }) {
  const isData = (r: Rbac) => /Storage Blob Data/i.test(r.roleDefinitionName);
  const columns: Column<Rbac>[] = [
    { key: 'roleDefinitionName', header: 'Role', filter: 'select', value: (r) => r.roleDefinitionName, render: (r) => <span className={'tag ' + (isData(r) ? 'tag-adls' : 'tag-other')}>{r.roleDefinitionName}</span> },
    { key: 'plane', header: 'Plane', filter: 'select', value: (r) => (isData(r) ? 'data' : 'control'), render: (r) => <span className={'tag ' + (isData(r) ? 'tag-warn' : 'tag-other')}>{isData(r) ? 'data-plane' : 'control-plane'}</span> },
    { key: 'principalType', header: 'Principal type', filter: 'select', value: (r) => r.principalType },
    { key: 'principalId', header: 'Principal', value: (r) => r.principalId, render: (r) => <span className="mono dim">{r.principalId}</span> },
    { key: 'scope', header: 'Scope', value: (r) => r.scope, render: (r) => <span className="mono dim">{r.scope.split('/').slice(-2).join('/')}</span> },
  ];
  return (
    <>
      <div className="view-note info">
        <b>Existing Azure role assignments on the storage account</b> — a separate permission system from the
        folder ACLs, and <b>not</b> the RBAC model proposed in Tab 2. <b>data‑plane</b> roles
        (<span className="mono">Storage Blob Data *</span>) grant access to the data and bypass ACLs.
      </div>
      <DataTable rows={rbac} columns={columns} exportName="storage-roles" initialFilters={initial} />
    </>
  );
}
