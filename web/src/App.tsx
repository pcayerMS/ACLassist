import { useEffect, useState, useCallback } from 'react';
import type { Inventory } from './types';
import { loadInventory } from './data';
import { InventoryTab } from './components/InventoryTab';
import { PropositionTab } from './components/PropositionTab';
import { FileLoader } from './components/FileLoader';

type Tab = 'inventory' | 'proposition';
type Status = 'loading' | 'need-file' | 'ready' | 'error';

export default function App() {
  const [inv, setInv] = useState<Inventory | null>(null);
  const [status, setStatus] = useState<Status>('loading');
  const [err, setErr] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('inventory');

  useEffect(() => {
    // Server/dev mode: try to fetch a co-located inventory.json. If unavailable (e.g. the file was
    // opened directly as file://), fall back to letting the user pick the file the scan produced.
    loadInventory()
      .then((i) => { setInv(i); setStatus('ready'); })
      .catch(() => setStatus('need-file'));
  }, []);

  const handleInventory = useCallback((i: Inventory) => { setInv(i); setStatus('ready'); setErr(null); }, []);
  const handleError = useCallback((m: string) => { setErr(m); setStatus('error'); }, []);

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
        {status === 'ready' && (
          <nav className="tabs">
            <button className={tab === 'inventory' ? 'tab active' : 'tab'} onClick={() => setTab('inventory')}>1 · Inventory</button>
            <button className={tab === 'proposition' ? 'tab active' : 'tab'} onClick={() => setTab('proposition')}>2 · Proposition</button>
          </nav>
        )}
        <div className="top-right">
          {status === 'ready' && <FileLoader compact onLoad={handleInventory} onError={handleError} />}
          <div className="badge-readonly" title="This dashboard only reads a local snapshot.">READ-ONLY</div>
        </div>
      </header>

      <main className="content">
        {status === 'loading' && <div className="loading">Loading…</div>}
        {(status === 'need-file' || status === 'error') && (
          <FileLoader onLoad={handleInventory} onError={handleError} error={err} />
        )}
        {status === 'ready' && inv && tab === 'inventory' && <InventoryTab inv={inv} />}
        {status === 'ready' && inv && tab === 'proposition' && <PropositionTab inv={inv} />}
      </main>

      {status === 'ready' && inv && (
        <footer className="statusbar">
          <span>Target <b>{inv.meta.target.storageAccount}</b> / {inv.meta.target.fileSystem}</span>
          <span>Scanned {new Date(inv.meta.generatedUtc).toLocaleString()}</span>
          <span className={isSample ? 'chip chip-warn' : 'chip'}>{isSample ? '⚠ sample data' : 'read-only snapshot'}</span>
        </footer>
      )}
    </div>
  );
}
