import { useMemo, useState, type ReactNode } from 'react';

export interface Column<T> {
  key: string;
  header: string;
  render?: (row: T) => ReactNode;
  value?: (row: T) => string | number;
}

interface Props<T> {
  rows: T[];
  columns: Column<T>[];
  searchText: (row: T) => string;
  pageSize?: number;
}

export function DataTable<T>({ rows, columns, searchText, pageSize = 50 }: Props<T>) {
  const [q, setQ] = useState('');
  const [page, setPage] = useState(0);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return rows;
    return rows.filter((r) => searchText(r).toLowerCase().includes(needle));
  }, [rows, q, searchText]);

  const pages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const cur = Math.min(page, pages - 1);
  const slice = filtered.slice(cur * pageSize, cur * pageSize + pageSize);

  return (
    <div className="table-wrap">
      <div className="table-toolbar">
        <input
          className="search"
          placeholder="Search…"
          value={q}
          onChange={(e) => { setQ(e.target.value); setPage(0); }}
        />
        <span className="count">{filtered.length.toLocaleString()} rows</span>
        <div className="pager">
          <button disabled={cur === 0} onClick={() => setPage(cur - 1)}>‹</button>
          <span>{cur + 1} / {pages}</span>
          <button disabled={cur >= pages - 1} onClick={() => setPage(cur + 1)}>›</button>
        </div>
      </div>
      <div className="table-scroll">
        <table>
          <thead>
            <tr>{columns.map((col) => <th key={col.key}>{col.header}</th>)}</tr>
          </thead>
          <tbody>
            {slice.map((row, i) => (
              <tr key={i}>
                {columns.map((col) => (
                  <td key={col.key}>
                    {col.render ? col.render(row) : col.value ? col.value(row) : String((row as Record<string, unknown>)[col.key] ?? '')}
                  </td>
                ))}
              </tr>
            ))}
            {slice.length === 0 && (
              <tr><td className="empty" colSpan={columns.length}>No matching rows.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
