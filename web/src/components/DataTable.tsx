import { useEffect, useMemo, useState, type ReactNode } from 'react';
import writeXlsxFile from 'write-excel-file/browser';

export interface Column<T> {
  key: string;
  header: string;
  value: (row: T) => string | number;
  render?: (row: T) => ReactNode;
  filter?: 'text' | 'select' | 'none';
  help?: string;
}

interface Props<T> {
  rows: T[];
  columns: Column<T>[];
  exportName?: string;
  initialFilters?: Record<string, string>;
  pageSize?: number;
}

export function DataTable<T>({ rows, columns, exportName = 'export', initialFilters, pageSize = 50 }: Props<T>) {
  const [filters, setFilters] = useState<Record<string, string>>(initialFilters ?? {});
  const [sort, setSort] = useState<{ key: string; dir: 1 | -1 } | null>(null);
  const [page, setPage] = useState(0);

  useEffect(() => { setFilters(initialFilters ?? {}); setPage(0); }, [initialFilters]);

  const colByKey = useMemo(() => {
    const m: Record<string, Column<T>> = {};
    for (const c of columns) m[c.key] = c;
    return m;
  }, [columns]);

  const selectOptions = useMemo(() => {
    const o: Record<string, string[]> = {};
    for (const c of columns) if (c.filter === 'select') o[c.key] = Array.from(new Set(rows.map((r) => String(c.value(r))))).sort();
    return o;
  }, [columns, rows]);

  const filtered = useMemo(() => {
    let out = rows;
    for (const [key, val] of Object.entries(filters)) {
      if (!val) continue;
      const c = colByKey[key];
      if (!c) continue;
      const needle = val.toLowerCase();
      const exact = c.filter === 'select';
      out = out.filter((r) => {
        const v = String(c.value(r)).toLowerCase();
        return exact ? v === needle : v.includes(needle);
      });
    }
    if (sort) {
      const c = colByKey[sort.key];
      if (c) {
        out = [...out].sort((a, b) => {
          const va = c.value(a), vb = c.value(b);
          if (va < vb) return -sort.dir;
          if (va > vb) return sort.dir;
          return 0;
        });
      }
    }
    return out;
  }, [rows, filters, sort, colByKey]);

  const pages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const cur = Math.min(page, pages - 1);
  const slice = filtered.slice(cur * pageSize, cur * pageSize + pageSize);
  const active = Object.entries(filters).filter(([, v]) => v);

  const setColFilter = (k: string, v: string) => { setFilters((f) => ({ ...f, [k]: v })); setPage(0); };
  const toggleSort = (k: string) => setSort((s) => (s && s.key === k ? (s.dir === 1 ? { key: k, dir: -1 } : null) : { key: k, dir: 1 }));

  async function doExport(which: 'filtered' | 'all') {
    const data = which === 'filtered' ? filtered : rows;
    const schema = columns.map((c) => ({
      column: c.header,
      type: String,
      value: (r: T) => { const v = c.value(r); return v === null || v === undefined ? '' : String(v); },
    }));
    const write = writeXlsxFile as unknown as (d: unknown, o: unknown) => Promise<void>;
    await write(data, { schema, fileName: `aclassist-${exportName}.xlsx` });
  }

  return (
    <div className="table-wrap">
      <div className="table-toolbar">
        <span className="count">{filtered.length.toLocaleString()} / {rows.length.toLocaleString()} rows</span>
        {active.length > 0 && (
          <div className="chips">
            {active.map(([k, v]) => (
              <button className="chip-f" key={k} onClick={() => setColFilter(k, '')} title="remove filter">{colByKey[k]?.header}: {v} ✕</button>
            ))}
            <button className="linkbtn" onClick={() => { setFilters({}); setPage(0); }}>clear all</button>
          </div>
        )}
        <div className="toolbar-right">
          <button className="btn" onClick={() => doExport('filtered')} title="Export the filtered rows to Excel">⤓ Export filtered</button>
          <button className="btn ghost" onClick={() => doExport('all')} title="Export all rows to Excel">Export all</button>
          <div className="pager">
            <button disabled={cur === 0} onClick={() => setPage(cur - 1)}>‹</button>
            <span>{cur + 1} / {pages}</span>
            <button disabled={cur >= pages - 1} onClick={() => setPage(cur + 1)}>›</button>
          </div>
        </div>
      </div>
      <div className="table-scroll">
        <table>
          <thead>
            <tr>
              {columns.map((c) => (
                <th key={c.key} className={'sortable' + (c.help ? ' has-help' : '')} title={c.help} onClick={() => toggleSort(c.key)}>
                  <span className="th-label">{c.header}</span><span className="sort-ind">{sort?.key === c.key ? (sort.dir === 1 ? ' ▲' : ' ▼') : ''}</span>
                </th>
              ))}
            </tr>
            <tr className="filter-row">
              {columns.map((c) => (
                <th key={c.key}>
                  {c.filter === 'none' ? null : c.filter === 'select' ? (
                    <select value={filters[c.key] ?? ''} onChange={(e) => setColFilter(c.key, e.target.value)}>
                      <option value="">all</option>
                      {selectOptions[c.key]?.map((o) => <option key={o} value={o}>{o}</option>)}
                    </select>
                  ) : (
                    <input value={filters[c.key] ?? ''} onChange={(e) => setColFilter(c.key, e.target.value)} placeholder="filter…" />
                  )}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {slice.map((row, i) => (
              <tr key={i}>{columns.map((c) => <td key={c.key}>{c.render ? c.render(row) : String(c.value(row))}</td>)}</tr>
            ))}
            {slice.length === 0 && <tr><td className="empty" colSpan={columns.length}>No matching rows.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  );
}
