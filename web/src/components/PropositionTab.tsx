import type { Inventory } from '../types';

export function PropositionTab({ inv }: { inv: Inventory }) {
  const orphans = inv.meta.counts.orphanGroups ?? 0;
  const groups = inv.meta.counts.groups ?? 0;
  return (
    <div className="tabpanel">
      <div className="placeholder">
        <div className="placeholder-tag">Coming in M4 / M5</div>
        <h2>AI Proposition</h2>
        <p>
          This tab will present the AI‑generated, <b>user‑editable</b> RBAC consolidation model — redundant‑group
          clustering, role personas, quantified savings, and a before→after map — driven by GitHub Copilot over
          <code> analysis.json</code> and rendered from <code>recommendations.json</code>, with an Excel round‑trip
          for approve / modify / reject.
        </p>
        <div className="teaser">
          <div className="teaser-num">{orphans.toLocaleString()}</div>
          <div className="teaser-txt">empty / unused groups in this inventory are candidates to retire<br />(≈ {groups ? Math.round((orphans / groups) * 100) : 0}% of all groups).</div>
        </div>
      </div>
    </div>
  );
}
