import { useEffect, useState } from 'react';
import type { Inventory } from './types';
import { loadInventory } from './data';
import { InventoryTab } from './components/InventoryTab';
import { PropositionTab } from './components/PropositionTab';

type Tab = 'inventory' | 'proposition';

export default function App() {
  const [inv, setInv] = useState<Inventory | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('inventory');

  useEffect(() => {
    loadInventory().then(setInv).catch((e) => setErr(String(e?.message ?? e)));
  }, []);

  const isSample = inv?.meta.notes?.[0]?.startsWith('SAMPLE');

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">ACL</span>
          <div>
            <div className="brand-title">ACLassist</div>
            <div className="brand-sub">ADLS Gen2 ACL → RBAC assessment</div>
          </div>
        </div>
        <nav className="tabs">
          <button className={tab === 'inventory' ? 'tab active' : 'tab'} onClick={() => setTab('inventory')}>1 · Inventory</button>
          <button className={tab === 'proposition' ? 'tab active' : 'tab'} onClick={() => setTab('proposition')}>2 · Proposition</button>
        </nav>
        <div className="badge-readonly" title="This dashboard only reads a local snapshot.">READ-ONLY</div>
      </header>

      <main className="content">
        {err && (
          <div className="error">
            <b>Couldn't load the inventory:</b> {err}
            <div className="error-hint">Run <code>engine/Invoke-Scan.ps1</code> (or <code>npm run generate-sample</code> for demo data), then reload.</div>
          </div>
        )}
        {!err && !inv && <div className="loading">Loading inventory…</div>}
        {inv && tab === 'inventory' && <InventoryTab inv={inv} />}
        {inv && tab === 'proposition' && <PropositionTab inv={inv} />}
      </main>

      {inv && (
        <footer className="statusbar">
          <span>Target <b>{inv.meta.target.storageAccount}</b> / {inv.meta.target.fileSystem}</span>
          <span>Scanned {new Date(inv.meta.generatedUtc).toLocaleString()}</span>
          <span className={isSample ? 'chip chip-warn' : 'chip'}>{isSample ? '⚠ sample data' : 'read-only snapshot'}</span>
        </footer>
      )}
    </div>
  );
}
