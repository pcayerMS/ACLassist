import { useCallback, useRef, useState } from 'react';
import type { Inventory } from '../types';

interface Props {
  onLoad: (inv: Inventory) => void;
  onError: (msg: string) => void;
  error?: string | null;
  compact?: boolean;
}

function readFile(file: File, onLoad: (inv: Inventory) => void, onError: (m: string) => void) {
  file.text()
    .then((t) => {
      try {
        const data = JSON.parse(t);
        if (!data?.meta || !Array.isArray(data.folders) || !Array.isArray(data.groups)) {
          onError('That file does not look like an inventory.json (missing meta / folders / groups).');
          return;
        }
        onLoad(data as Inventory);
      } catch {
        onError('Could not parse that file as JSON.');
      }
    })
    .catch(() => onError('Could not read that file.'));
}

export function FileLoader({ onLoad, onError, error, compact }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [drag, setDrag] = useState(false);
  const pick = useCallback((f?: File | null) => { if (f) readFile(f, onLoad, onError); }, [onLoad, onError]);

  const input = (
    <input
      ref={inputRef}
      type="file"
      accept=".json,application/json"
      style={{ display: 'none' }}
      onChange={(e) => pick(e.target.files?.[0])}
    />
  );

  if (compact) {
    return (
      <>
        {input}
        <button className="tab" onClick={() => inputRef.current?.click()} title="Load a different inventory.json">Load file…</button>
      </>
    );
  }

  return (
    <div className="loader-screen">
      <div
        className={'dropzone' + (drag ? ' drag' : '')}
        onDragOver={(e) => { e.preventDefault(); setDrag(true); }}
        onDragLeave={() => setDrag(false)}
        onDrop={(e) => { e.preventDefault(); setDrag(false); pick(e.dataTransfer.files?.[0]); }}
        onClick={() => inputRef.current?.click()}
      >
        {input}
        <div className="dz-icon">⤓</div>
        <div className="dz-title">Open your <code>inventory.json</code></div>
        <div className="dz-sub">Drag &amp; drop it here, or click to browse.</div>
        {error && <div className="dz-error">{error}</div>}
      </div>
      <div className="loader-help">
        Produce it by running the read‑only scan (<code>engine/Invoke-Scan.ps1</code>), which writes
        <code> data/inventory.json</code>. Everything here runs locally in your browser — nothing is uploaded.
      </div>
    </div>
  );
}
