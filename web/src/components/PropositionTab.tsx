import { useEffect, useRef, useState } from 'react';
import type { Recommendations, RecRole } from '../types';
import { loadRecommendations } from '../data';
import { DataTable, type Column } from './DataTable';

type Status = 'loading' | 'need-file' | 'ready' | 'error';

function decisionClass(d?: string) {
  if (d === 'Approve') return 'tag-ok';
  if (d === 'Reject') return 'tag-warn';
  if (d === 'Modify') return 'tag-dormant';
  return 'tag-dim';
}

export function PropositionTab() {
  const [rec, setRec] = useState<Recommendations | null>(null);
  const [status, setStatus] = useState<Status>('loading');
  const [err, setErr] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const [drag, setDrag] = useState(false);

  useEffect(() => {
    loadRecommendations().then((r) => { setRec(r); setStatus('ready'); }).catch(() => setStatus('need-file'));
  }, []);

  function accept(data: unknown) {
    const d = data as Recommendations;
    if (!d || !d.meta || !d.summary || !Array.isArray(d.roles)) {
      setErr('That file does not look like a recommendations.json (missing meta / summary / roles).');
      setStatus('error');
      return;
    }
    setRec(d); setErr(null); setStatus('ready');
  }
  function pick(f?: File | null) {
    if (!f) return;
    f.text().then((t) => { try { accept(JSON.parse(t)); } catch { setErr('Could not parse that file as JSON.'); setStatus('error'); } })
      .catch(() => { setErr('Could not read that file.'); setStatus('error'); });
  }

  if (status === 'loading') return <div className="loading">Loading…</div>;

  if (status !== 'ready' || !rec) {
    return (
      <div className="tabpanel">
        <div className="loader-screen">
          <div
            className={'dropzone' + (drag ? ' drag' : '')}
            onDragOver={(e) => { e.preventDefault(); setDrag(true); }}
            onDragLeave={() => setDrag(false)}
            onDrop={(e) => { e.preventDefault(); setDrag(false); pick(e.dataTransfer.files?.[0]); }}
            onClick={() => inputRef.current?.click()}
          >
            <input ref={inputRef} type="file" accept=".json,application/json" style={{ display: 'none' }} onChange={(e) => pick(e.target.files?.[0])} />
            <div className="dz-icon">◆</div>
            <div className="dz-title">Open your <code>recommendations.json</code></div>
            <div className="dz-sub">Drag &amp; drop it here, or click to browse.</div>
            {err && <div className="dz-error">{err}</div>}
          </div>
          <div className="loader-help">
            Produce it by running the AI proposition prompt (<code>ai/prompts/assess.prompt.md</code>) in GitHub
            Copilot — it reads <code>data/analysis.json</code> and writes <code>data/recommendations.json</code> +
            the editable <code>data/proposed-model.xlsx</code>. Everything runs locally — nothing is uploaded.
          </div>
        </div>
      </div>
    );
  }

  const s = rec.summary;
  const roleCount = s.proposedRoleCount ?? rec.roles.length;
  const decided = rec.roles.filter((r) => r.decision).length;

  const columns: Column<RecRole>[] = [
    { key: 'decision', header: 'Decision', filter: 'select', help: 'Your call, edited in proposed-model.xlsx: Approve / Modify / Reject (blank = undecided).', value: (r) => r.decision || '—', render: (r) => <span className={'tag ' + decisionClass(r.decision)}>{r.decision || '—'}</span> },
    { key: 'displayName', header: 'Proposed role', help: 'Friendly name of the consolidated role.', value: (r) => r.displayName, render: (r) => <span className="mono">{r.displayName}</span> },
    { key: 'scope', header: 'Scope', filter: 'select', help: 'Department / domain the role covers.', value: (r) => r.scope },
    { key: 'accessLevel', header: 'Access', filter: 'select', help: 'Reader / Contributor / Owner.', value: (r) => r.accessLevel },
    { key: 'azureRole', header: 'Azure role', filter: 'select', help: 'Suggested Azure built-in data-plane role.', value: (r) => r.azureRole },
    { key: 'replacesGroupCount', header: 'Replaces', help: 'How many existing ACL groups this one role consolidates.', value: (r) => r.replacesGroupCount },
    { key: 'folderScope', header: 'Folder scope', help: 'Path prefix the role applies to.', value: (r) => r.folderScope, render: (r) => <span className="mono">{r.folderScope}</span> },
    { key: 'confidence', header: 'Confidence', filter: 'select', help: 'AI confidence in this consolidation.', value: (r) => r.confidence },
    { key: 'rationale', header: 'Rationale', help: 'Why this role is proposed.', value: (r) => r.rationale },
  ];

  return (
    <div className="tabpanel">
      <section className="kpis">
        <div className="kpi"><div className="kpi-value">{(s.currentGroups ?? 0).toLocaleString()}</div><div className="kpi-label">Groups today</div><div className="kpi-sub">current ACL groups</div></div>
        <div className="kpi"><div className="kpi-value">{roleCount.toLocaleString()}</div><div className="kpi-label">Proposed roles</div><div className="kpi-sub">RBAC-style</div></div>
        <div className="kpi kpi-good"><div className="kpi-value">{(s.groupsEliminated ?? 0).toLocaleString()}</div><div className="kpi-label">Groups retired</div><div className="kpi-sub">if approved</div></div>
        <div className="kpi kpi-good"><div className="kpi-value">{s.reductionPct ?? 0}%</div><div className="kpi-label">Reduction</div><div className="kpi-sub">fewer groups</div></div>
      </section>

      <div className="beforeafter">
        <div className="ba-side"><div className="ba-num">{(s.currentGroups ?? 0).toLocaleString()}</div><div className="ba-cap">ACL groups today</div></div>
        <div className="ba-arrow">→</div>
        <div className="ba-side ba-after"><div className="ba-num">{roleCount.toLocaleString()}</div><div className="ba-cap">RBAC-style roles</div></div>
        {s.headline && <div className="ba-headline">{s.headline}</div>}
      </div>

      <div className="view-note info">
        <b>You are in control.</b> These are AI <b>proposals</b>, not changes. Review each role and set the
        <b> Decision</b> (Approve / Modify / Reject) in <span className="mono">data/proposed-model.xlsx</span>
        {decided > 0 ? ` — ${decided} of ${rec.roles.length} decided so far.` : '.'} <b>Nothing is applied</b> —
        remediation is a later phase.
      </div>

      <DataTable rows={rec.roles} columns={columns} exportName="proposed-roles" />

      {rec.findings && rec.findings.length > 0 && (
        <div className="findings">
          <h3>Findings</h3>
          <ul>
            {rec.findings.map((f) => (
              <li key={f.id}><span className={'sev sev-' + (f.severity || 'info')}>{f.severity}</span> <b>{f.title}</b> — {f.detail}</li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
