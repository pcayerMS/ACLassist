import type { Inventory } from '../types';

function pct(n: number, d: number) { return d ? Math.round((n / d) * 100) : 0; }

export function KpiCards({ inv }: { inv: Inventory }) {
  const c = inv.meta.counts;
  const orphanPct = pct(c.orphanGroups ?? 0, c.groups ?? 0);
  const avgAces = c.folders ? (c.aces / c.folders).toFixed(1) : '0';

  const cards: { label: string; value: number; sub: string; warn?: boolean }[] = [
    { label: 'Folders', value: c.folders ?? 0, sub: 'directories scanned' },
    { label: 'ACL entries', value: c.aces ?? 0, sub: `${avgAces} avg / folder` },
    { label: 'Groups', value: c.groups ?? 0, sub: 'Entra security groups' },
    { label: 'Users', value: c.users ?? 0, sub: 'principals' },
    { label: 'Orphan groups', value: c.orphanGroups ?? 0, sub: `${orphanPct}% of all groups`, warn: orphanPct > 50 },
    { label: 'Group nesting', value: c.groupNesting ?? 0, sub: 'parent → child edges' },
    { label: 'Memberships', value: c.memberships ?? 0, sub: 'user → group edges' },
    { label: 'RBAC assignments', value: c.rbacAssignments ?? 0, sub: 'data / mgmt plane' },
  ];

  return (
    <section className="kpis">
      {cards.map((k) => (
        <div key={k.label} className={'kpi' + (k.warn ? ' kpi-warn' : '')}>
          <div className="kpi-value">{k.value.toLocaleString()}</div>
          <div className="kpi-label">{k.label}</div>
          <div className="kpi-sub">{k.sub}</div>
        </div>
      ))}
    </section>
  );
}
