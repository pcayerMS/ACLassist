# Changelog

All notable changes to **ACLassist** (ADLS ACL → RBAC assessment). Newest first.
Mirrored in git history: https://github.com/pcayerMS/ACLassist

---

## 2026-07-20 — Customer-usable: interactive setup, no hardcoded target
- **New `engine/Initialize-Config.ps1`** — interactive, READ-ONLY setup that writes `config/config.json`
  (git-ignored, **local only — never committed**). You type tenant + subscription, then **pick the storage
  account and container from lists** (resource group auto-derived). Re-runs **propose your previously
  entered values as defaults** (press Enter to keep each). `Invoke-Scan.ps1` auto-launches it when config
  is missing/incomplete and gains a **`-Reconfigure`** switch.
- **No more hardcoded lab target.** `Get-ScanConfig` no longer copies the sample verbatim; it validates and
  rejects placeholder values. `config.sample.json`, `config.schema.json`, and the demo-data generator are
  scrubbed to generic placeholders (`<your-…>`, `contoso`) — nothing ships pointing at the lab.
- **Auth simplified to interactive OAuth only — SAS removed** from the engine, config, and schema (per
  request). Optional **`auth.loginHint`** (UPN) pre-fills the sign-in; no secret is ever stored.
- Added `Test-ScanConfigComplete` + BOM-free `Write-JsonFile` helpers. Docs updated (README, RUNBOOK,
  ARCHITECTURE, SECURITY-READONLY, PLAN).

## 2026-07-20 — Engine: friendly module preflight
- **`Assert-EngineModules`** (in `Common.ps1`, called at the start of `Invoke-Scan.ps1`) now verifies the
  read-only `Az.*` / `Microsoft.Graph.*` modules are available **to the current PowerShell edition** before
  the scan runs. A missing module now throws an actionable message ("run `Assert-Prerequisites.ps1`, or use
  `pwsh`") instead of the cryptic `Get-AzContext is not recognized` — the failure seen when running the scan
  under Windows PowerShell 5.1 on a VM where Az is only installed for PowerShell 7. Also imports the
  entry-point modules so cmdlet auto-loading is guaranteed.

## 2026-07-17 — Behavioural group classification + effective-access-aware status
- **`kind` (name prefix) is no longer the semantic driver.** Each group now carries a naming-independent
  **`role`** — `access` (on a folder ACL), `role` (aggregates members), `hybrid` (both), `unused` (neither) —
  derived from *observed* facts, so the tool works on **any** customer's naming, not just Air Canada's
  `ADLS_`/`PRD_`.
- **New effective-access-aware `status`:** `active`, **`unreachable`** (on a folder ACL but **no user is an
  effective member** — a dead grant), or `unused`. Computed via **transitive membership** (engine and sample
  generator share the same reachability walk). This replaces the crude "orphan = empty OR not-on-ACL" test
  that mislabeled a two-tier estate, where role groups *and* resource groups both looked "orphan".
- **Engine** (`Export-Inventory.ps1` + `Common.ps1`): groups gain `role`, `status`, `onAce`, `memberCount`,
  `reachable`; `meta.counts` gains `accessGroups`, `roleGroups`, `unreachableGroups`. `hygiene.orphanGroups`
  now lists non-active groups (still carries `emptyMembers`/`notOnAnyAce` for the analyzer).
- **Dashboard:** Groups table shows **Role**, **Status**, **Naming** (the old prefix, kept as a label) and
  **Members**; the KPI card is relabeled **Unreachable**; the sprawl callout reads "N of M access groups reach no user".
- On the sample: **2,304 access + 8 role groups; 2,286 unreachable** dead grants, 26 active.

## 2026-07-17 — Phase A: Dashboard Tab 1 upgrades
- **Per‑column filtering** on every inventory table — free‑text inputs and, for categorical columns,
  **select dropdowns** — replacing the single global search. Active filters render as removable **chips**
  with a **clear all**.
- **Real Excel export** (`.xlsx`, via `write-excel-file` — MIT, 0 vulns): **Export filtered** (respects the
  current filters/sort) or **Export all**, on every table.
- **Click‑to‑sort** column headers.
- **Clickable KPI cards** — each card jumps to the matching sub‑table and pre‑applies the relevant filter
  (e.g. *Orphan groups* → Groups filtered to `status = orphan`).
- **New sub‑tables:** **Group nesting** (parent → member group) and **Memberships** (member → group).
- **RBAC tab relabeled “Storage roles”** with an info note clarifying these are the *existing* Azure role
  assignments on the storage account (data‑ vs control‑plane), **not** the RBAC model proposed in Tab 2.
- Single‑file dashboard grew to ~236 KB (bundles the offline Excel writer). Still **zero‑install**.

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
