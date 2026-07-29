import { useState } from 'react';
import type { Proposal, ProposedRole, ProposedGroupAction, ProposedUserFlag } from '../types';
import { DataTable, type Column } from './DataTable';

type Sub = 'roles' | 'actions' | 'users';

const ACTION_TITLE: Record<string, string> = {
  retire_dormant: 'On a folder ACL but no user is an effective member — a dead grant',
  retire_unused: 'Not on any ACL and has no members — grants nothing to anyone',
  merge_duplicate: 'Grant footprint identical to the surviving group',
  flatten_nesting: 'Pass-through only — no ACL, no direct users',
  map_to_role: 'Covered by a proposed role for this scope and access level',
  keep: 'Kept as-is',
};

function safeTag(safe: boolean) {
  return safe
    ? <span className="tag tag-ok" title="Provably no user gains or loses access.">safe</span>
    : <span className="tag tag-dormant" title="Would widen access — check the &quot;New folders&quot; column.">review</span>;
}

export function PropositionTab({ proposal }: { proposal: Proposal | null }) {
  const [sub, setSub] = useState<Sub>('roles');

  if (!proposal) {
    return (
      <div className="tabpanel">
        <div className="loader-screen">
          <div className="dropzone" style={{ cursor: 'default' }}>
            <div className="dz-icon">◆</div>
            <div className="dz-title">No proposition in this database yet</div>
            <div className="dz-sub">Tab 1 loaded fine — this database just has no proposal tables.</div>
          </div>
          <div className="loader-help">
            Build one offline (no Azure, no AI) with <code>pwsh -File ./engine/Invoke-Proposition.ps1</code>,
            then reload <code>data/aclassist.db</code> here. It writes the proposed model straight into the
            same database, so Tab 1 and Tab 2 always come from one file.
          </div>
        </div>
      </div>
    );
  }

  const s = proposal.summary;
  const subs: { key: Sub; label: string; count: number }[] = [
    { key: 'roles', label: 'Proposed roles', count: proposal.roles.length },
    { key: 'actions', label: 'Group actions', count: proposal.actions.length },
    { key: 'users', label: 'Over-membership', count: proposal.userFlags.length },
  ];

  return (
    <div className="tabpanel">
      <section className="kpis">
        <div className="kpi"><div className="kpi-value">{s.currentGroups.toLocaleString()}</div><div className="kpi-label">Groups today</div><div className="kpi-sub">before any change</div></div>
        <div className="kpi kpi-good"><div className="kpi-value">{s.safeRemovable.toLocaleString()}</div><div className="kpi-label">Safely removable</div><div className="kpi-sub">no access change</div></div>
        <div className="kpi kpi-good"><div className="kpi-value">{s.groupsAfterSafe.toLocaleString()}</div><div className="kpi-label">Groups after safe pass</div><div className="kpi-sub">{s.safeReductionPct}% fewer</div></div>
        <div className="kpi"><div className="kpi-value">{s.proposedRoleCount.toLocaleString()}</div><div className="kpi-label">Proposed roles</div><div className="kpi-sub">{s.rolesNeedingReview} need review</div></div>
      </section>

      <div className="beforeafter">
        <div className="ba-side"><div className="ba-num">{s.currentGroups.toLocaleString()}</div><div className="ba-cap">groups today</div></div>
        <div className="ba-arrow">→</div>
        <div className="ba-side ba-after"><div className="ba-num">{s.groupsAfterSafe.toLocaleString()}</div><div className="ba-cap">after access-safe actions</div></div>
        <div className="ba-arrow">→</div>
        <div className="ba-side ba-after"><div className="ba-num">{s.groupsAfterFull.toLocaleString()}</div><div className="ba-cap">after full consolidation</div></div>
        <div className="ba-headline">
          Retiring dead grants alone removes {s.safeRemovable.toLocaleString()} of {s.currentGroups.toLocaleString()} groups
          ({s.safeReductionPct}%) with <b>no change to anyone's access</b>.
        </div>
      </div>

      <div className="view-note info">
        <b>You are in control — nothing is applied.</b> Every number here is computed by
        <span className="mono"> engine/sql/propose.sql</span> from the scanned data; none of it is generated or guessed.
        Rows marked <span className="tag tag-ok">safe</span> provably change no user's effective access. Rows marked
        <span className="tag tag-dormant">review</span> would <b>widen</b> access — the <b>New folders</b> column says
        exactly how many folders each one would newly expose.
      </div>

      <div className="subtabs">
        {subs.map((x) => (
          <button key={x.key} className={sub === x.key ? 'subtab active' : 'subtab'} onClick={() => setSub(x.key)}>
            {x.label} <span className="subtab-count">{x.count.toLocaleString()}</span>
          </button>
        ))}
      </div>

      {sub === 'roles' && <RolesTable roles={proposal.roles} />}
      {sub === 'actions' && <ActionsTable actions={proposal.actions} />}
      {sub === 'users' && <UsersTable flags={proposal.userFlags} />}
    </div>
  );
}

function RolesTable({ roles }: { roles: ProposedRole[] }) {
  const columns: Column<ProposedRole>[] = [
    { key: 'decision', header: 'Decision', filter: 'select', help: 'Your call — Approve / Modify / Reject. Blank = undecided. Export to Excel to record decisions.', value: (r) => r.decision || '—', render: (r) => <span className={'tag ' + (r.decision === 'Approve' ? 'tag-ok' : r.decision === 'Reject' ? 'tag-warn' : r.decision === 'Modify' ? 'tag-dormant' : 'tag-dim')}>{r.decision || '—'}</span> },
    { key: 'safe', header: 'Safety', filter: 'select', help: 'safe = provably no access change. review = would widen access; see New folders.', value: (r) => (r.accessSafe ? 'safe' : 'review'), render: (r) => safeTag(r.accessSafe) },
    { key: 'displayName', header: 'Proposed role', help: 'Friendly name for the consolidated role.', value: (r) => r.displayName, render: (r) => <span className="mono">{r.displayName}</span> },
    { key: 'accessLevel', header: 'Access', filter: 'select', help: 'Access level derived from the POSIX permission bits the replaced groups grant.', value: (r) => r.accessLevel },
    { key: 'azureRole', header: 'Azure role', filter: 'select', help: 'Closest Azure built-in data-plane role. ADLS RBAC scopes to the container, so folder-level grants still need ACLs.', value: (r) => r.azureRole },
    { key: 'folderScope', header: 'Scope', help: 'Deepest folder that is an ancestor of every folder this role covers.', value: (r) => r.folderScope, render: (r) => <span className="mono">{r.folderScope}</span> },
    { key: 'replacesGroupCount', header: 'Replaces', filter: 'range', help: 'How many existing groups this one role replaces.', value: (r) => r.replacesGroupCount },
    { key: 'memberUserCount', header: 'Users', filter: 'range', help: 'Distinct users who would end up holding this role.', value: (r) => r.memberUserCount },
    { key: 'coveredFolderCount', header: 'Folders covered', filter: 'range', help: 'Folders the replaced groups actually grant on today.', value: (r) => r.coveredFolderCount },
    { key: 'newFolderCount', header: 'New folders', filter: 'range', help: 'Folders this role would expose that are NOT granted today. 0 = no widening.', value: (r) => r.newFolderCount, render: (r) => (r.newFolderCount > 0 ? <b className="mono">{r.newFolderCount}</b> : <span className="dim">0</span>) },
    { key: 'namedBy', header: 'Named by', filter: 'select', help: 'deterministic = generated by SQL. ai = an AI wrote the name/rationale (numbers are never AI-generated).', value: (r) => r.namedBy },
    { key: 'rationale', header: 'Rationale', help: 'Why this role is proposed.', value: (r) => r.rationale },
  ];
  return (
    <>
      <div className="view-note">A role replaces the active groups that grant the same access level within one base directory. Its scope is the <b>deepest common ancestor</b> of the folders those groups actually grant on, so it widens access as little as the data allows.</div>
      <DataTable rows={roles} columns={columns} exportName="proposed-roles" />
    </>
  );
}

function ActionsTable({ actions }: { actions: ProposedGroupAction[] }) {
  const columns: Column<ProposedGroupAction>[] = [
    { key: 'action', header: 'Action', filter: 'select', help: 'What is proposed for this group.', value: (a) => a.action, render: (a) => <span className={'tag tag-role-' + (a.action.indexOf('retire') === 0 ? 'unused' : a.action === 'keep' ? 'role' : 'access')} title={ACTION_TITLE[a.action]}>{a.action.replace(/_/g, ' ')}</span> },
    { key: 'safe', header: 'Safety', filter: 'select', help: 'safe = provably no access change for any user.', value: (a) => (a.accessSafe ? 'safe' : 'review'), render: (a) => safeTag(a.accessSafe) },
    { key: 'displayName', header: 'Group', help: 'Existing group display name.', value: (a) => a.displayName, render: (a) => <span className="mono">{a.displayName}</span> },
    { key: 'status', header: 'Status', filter: 'select', help: 'Effective-access status observed in the scan.', value: (a) => a.status },
    { key: 'observedRole', header: 'Observed role', filter: 'select', help: 'What the group does today: access / role / hybrid / unused.', value: (a) => a.observedRole },
    { key: 'memberCount', header: 'Members', filter: 'range', help: 'Direct members on the group today.', value: (a) => a.memberCount },
    { key: 'effectiveUserCount', header: 'Effective users', filter: 'range', help: 'Users who ultimately land in this group today.', value: (a) => a.effectiveUserCount },
    { key: 'target', header: 'Becomes', help: 'The role or surviving group this one folds into (blank when simply retired).', value: (a) => a.target, render: (a) => <span className="mono dim">{a.target}</span> },
    { key: 'reason', header: 'Why', help: 'The rule that produced this action.', value: (a) => a.reason },
  ];
  return (
    <>
      <div className="view-note">Every existing group gets exactly one disposition. The most conservative rule wins — a dead grant is retired rather than folded into a role.</div>
      <DataTable rows={actions} columns={columns} exportName="group-actions" />
    </>
  );
}

function UsersTable({ flags }: { flags: ProposedUserFlag[] }) {
  const columns: Column<ProposedUserFlag>[] = [
    { key: 'overThreshold', header: 'Flagged', filter: 'select', help: 'Whether the user is at or above the over-membership threshold.', value: (u) => (u.overThreshold ? 'yes' : 'no'), render: (u) => <span className={'tag ' + (u.overThreshold ? 'tag-warn' : 'tag-dim')}>{u.overThreshold ? 'yes' : 'no'}</span> },
    { key: 'upn', header: 'UPN', help: 'User principal name.', value: (u) => u.upn, render: (u) => <span className="mono">{u.upn}</span> },
    { key: 'displayName', header: 'Name', help: 'Display name.', value: (u) => u.displayName },
    { key: 'jobTitle', header: 'Job title', filter: 'select', help: 'Job title from the directory.', value: (u) => u.jobTitle },
    { key: 'directGroupCount', header: 'Direct groups', filter: 'range', help: 'Groups the user is a direct member of.', value: (u) => u.directGroupCount },
    { key: 'effectiveGroupCount', header: 'Effective groups', filter: 'range', help: 'Total groups reached including nesting — the real over-membership number.', value: (u) => u.effectiveGroupCount },
    { key: 'threshold', header: 'Threshold', help: 'The -OverMembershipThreshold used when the proposition was built.', value: (u) => u.threshold },
  ];
  return (
    <>
      <div className="view-note">Users carrying the most groups. Consolidation should bring <b>effective groups</b> down; this is the list to re-check after the model is applied in a later phase.</div>
      <DataTable rows={flags} columns={columns} exportName="over-membership" />
    </>
  );
}
