# Changelog

All notable changes to **ACLassist** (ADLS ACL → RBAC assessment). Newest first.
Mirrored in git history: https://github.com/pcayerMS/ACLassist

---

## 2026-07-17 — M3: Offline analyzer
- **Added `analyzer/Invoke-Analysis.ps1`** — dependency‑free PowerShell, fully offline (no Azure).
  Reads `data/inventory.json` (+ `inventory.jsonl`) and writes `data/analysis.json`:
  - duplicate‑grant group clusters (groups whose folder grants are identical),
  - orphan / empty / unused groups,
  - user **personas** clustered by effective (transitive) access,
  - a mechanical **role‑collapse model** (per department × access level) + **quantified savings**,
  - narrative‑ready findings for the AI layer.
- On the sample estate: **2,312 groups → 18 proposed roles (~99% reduction)**; 288 duplicate groups; 2,294 orphans.
- Docs: RUNBOOK step 5 (analyzer) + step 6 (AI, next); README status / quick‑start / layout updated.

## 2026-07-17 — Portability rework
- **Dashboard is now a single self‑contained HTML** (`dashboard/ACLassist.html`). The customer opens it in
  any browser and loads `inventory.json` via drag‑drop / file picker. **No Node, npm, server, or winget** on
  the customer machine. (Node stays a maintainer‑only build tool: `cd web && npm run portable`.)
- **Engine runs on built‑in Windows PowerShell 5.1** (PowerShell 7 no longer required): removed PS7‑only
  syntax (`? :`, `??`, `$IsWindows`); **BOM‑free UTF‑8 writes** (5.1's `-Encoding utf8` BOM broke browser `JSON.parse`).
- `Assert-Prerequisites.ps1`: dropped Node/winget checks; auto‑installs `Az.*` / `Microsoft.Graph.*` modules
  (bootstraps NuGet provider + trusts PSGallery on 5.1).
- Engine **auto‑creates `config/config.json`** from the sample when missing, and prints the target before the consent prompt.

## 2026-07-17 — M2: Dashboard, Tab 1 (Inventory)
- Added the Vite + React + TypeScript dashboard (`web/`): KPI cards, sprawl callout, and searchable
  Groups / Folders / Users / RBAC tables reading `data/inventory.json`.
- Added a portable demo‑data generator (`web/scripts/generate-sample.mjs`).

## 2026-07-16 — M1: Read‑only scan engine + REST rewrite
- Added the read‑only PowerShell scan engine (`engine/`): enumerates ADLS Gen2 ACLs + Entra
  groups / members / users / RBAC → `data/inventory.json` (+ `inventory.jsonl`).
- Switched ADLS reads to the DFS **REST API** (List Paths + `getAccessControl`) to bypass an Az.Storage
  `-UseConnectedAccount` token bug; added data‑plane 403 diagnostics and the `x-ms-acl` parser.
- Validated on the lab (private‑endpoint‑only ADLS): **391 folders, 2,312 groups, 51 users**.

## 2026-07-15 — M0: Scaffold + safety
- Repo scaffold, read‑only guarantee (operation allowlist + consent banner), config schema, and the
  prerequisite bootstrapper. Published to GitHub (`pcayerMS/ACLassist`).
