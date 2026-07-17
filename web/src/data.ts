import type { Inventory } from './types';

const base = import.meta.env.BASE_URL ?? '/';

export async function loadInventory(): Promise<Inventory> {
  const res = await fetch(`${base}inventory.json`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`could not load inventory.json (HTTP ${res.status})`);
  return res.json() as Promise<Inventory>;
}
