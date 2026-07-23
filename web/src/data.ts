import type { Inventory, Recommendations } from './types';

const base = import.meta.env.BASE_URL ?? '/';

export async function loadInventory(): Promise<Inventory> {
  const res = await fetch(`${base}inventory.json`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`could not load inventory.json (HTTP ${res.status})`);
  return res.json() as Promise<Inventory>;
}

export async function loadRecommendations(): Promise<Recommendations> {
  const res = await fetch(`${base}recommendations.json`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`could not load recommendations.json (HTTP ${res.status})`);
  return res.json() as Promise<Recommendations>;
}
