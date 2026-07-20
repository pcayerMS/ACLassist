import type { Inventory } from '../types';

export interface KpiTarget { sub: string; filter?: { col: string; val: string } }

function pct(n: number, d: number) { return d ? Math.round((n / d) * 100) : 0; }

export function KpiCards({ inv, onNavigate }: { inv: Inventory; onNavigate: (t: KpiTarget) => void }) {
  const c = inv.meta.counts;
  const dormant = c.dormantGroups ?? c.unreachableGroups ?? c.orphanGroups ?? 0;
  const accessBase = c.accessGroups ?? c.groups ?? 0;
  const dormantPct = pct(dormant, accessBase);
  const avgAces = c.folders ? (c.aces / c.folders).toFixed(1) : '0';

  const cards: { label: string; value: number; sub: string; warn?: boolean; target: KpiTarget }[] = [
    { label: 'Folders', value: c.folders ?? 0, sub: 'directories scanned', target: { sub: 'folders' } },
    { label: 'ACL entries', value: c.aces ?? 0, sub: `${avgAces} avg / folder`, target: { sub: 'folders' } },
    { label: 'Groups', value: c.groups ?? 0, sub: 'Entra security groups', target: { sub: 'groups' } },
    { label: 'Users', value: c.users ?? 0, sub: 'in-scope principals', target: { sub: 'users' } },
    { label: 'Dormant', value: dormant, sub: `${dormantPct}% of access groups`, warn: dormantPct > 50, target: { sub: 'groups', filter: { col: 'status', val: 'dormant' } } },
    { label: 'Group nesting', value: c.groupNesting ?? 0, sub: 'parent → child edges', target: { sub: 'nesting' } },
    { label: 'Memberships', value: c.memberships ?? 0, sub: 'user → group edges', target: { sub: 'memberships' } },
    { label: 'Storage roles', value: c.rbacAssignments ?? 0, sub: 'Azure RBAC on the account', target: { sub: 'rbac' } },
  ];

  return (
    <section className="kpis">
      {cards.map((k) => (
        <button key={k.label} className={'kpi' + (k.warn ? ' kpi-warn' : '')} onClick={() => onNavigate(k.target)} title="Open in the table below">
          <div className="kpi-value">{k.value.toLocaleString()}</div>
          <div className="kpi-label">{k.label}</div>
          <div className="kpi-sub">{k.sub}</div>
        </button>
      ))}
    </section>
  );
}
