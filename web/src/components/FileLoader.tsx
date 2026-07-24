import { useCallback, useRef, useState } from 'react';
import type { Inventory } from '../types';
import { loadInventoryFromDb } from '../data';

interface Props {
  onLoad: (inv: Inventory) => void;
  onError: (msg: string) => void;
  error?: string | null;
  compact?: boolean;
}

function readFile(file: File, onLoad: (inv: Inventory) => void, onError: (m: string) => void) {
  file.arrayBuffer()
    .then((buf) => {
      const bytes = new Uint8Array(buf);
      const magic = String.fromCharCode.apply(null, Array.from(bytes.slice(0, 15)));
      if (magic === 'SQLite format 3') {
        loadInventoryFromDb(bytes).then(onLoad).catch(() => onError('Could not read that database (is it an aclassist.db?).'));
        return;
      }
      try {
        const data = JSON.parse(new TextDecoder().decode(bytes));
        if (!data?.meta || !Array.isArray(data.folders) || !Array.isArray(data.groups)) {
          onError('That file is not an aclassist database (.db) or a valid inventory.');
          return;
        }
        onLoad(data as Inventory);
      } catch {
        onError('That file is not an aclassist database (.db).');
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
      accept=".db,.sqlite,.json,application/json"
      style={{ display: 'none' }}
      onChange={(e) => pick(e.target.files?.[0])}
    />
  );

  if (compact) {
    return (
      <>
        {input}
        <button className="tab" onClick={() => inputRef.current?.click()} title="Load a different aclassist.db">Load file…</button>
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
        <div className="dz-title">Open your <code>aclassist.db</code></div>
        <div className="dz-sub">Drag &amp; drop it here, or click to browse.</div>
        {error && <div className="dz-error">{error}</div>}
      </div>
      <div className="loader-help">
        Produce it by running the read‑only assessment (<code>engine/Invoke-Assessment.ps1</code>), which
        writes <code>data/aclassist.db</code>. Everything runs locally in your browser — nothing is uploaded.
      </div>
    </div>
  );
}
