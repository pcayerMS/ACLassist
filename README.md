# Air Canada — ADLS ACL → RBAC Assessment Tool

A **portable, read‑only** tool that inventories an Azure Data Lake Storage Gen2 (ADLS Gen2)
POSIX‑ACL + Microsoft Entra ID permission structure and uses AI (via GitHub Copilot) to propose a
simplified, RBAC‑style model. Ships as a git repo you clone, point at a target, and run.

> ## 🔒 READ‑ONLY
> This tool **only reads**. It enumerates ACLs, groups, and memberships to build an inventory.
> It will **never** create, modify, move, or delete anything in Azure or Microsoft Entra ID, and it
> performs **no remediation** in Phase 1. See [docs/SECURITY-READONLY.md](docs/SECURITY-READONLY.md).

## What it produces
- **Tab 1 — Inventory:** the real ACL/permission structure as a searchable list + interactive map.
- **Tab 2 — Proposition:** AI‑generated, fully user‑editable recommendations to consolidate the sprawl
  into an RBAC‑style model, with a before→after map. You approve/modify/reject everything.

## Prerequisites
- **PowerShell 7+**
- PowerShell modules: `Az.Accounts`, `Az.Storage`, `Az.Resources`, `Microsoft.Graph.Authentication`,
  `Microsoft.Graph.Groups`, `Microsoft.Graph.Users`
- **Node.js LTS** (for the analyzer + dashboard)

Run the checker — it offers to install anything missing (local installs only):

```powershell
pwsh ./engine/Assert-Prerequisites.ps1
```

## Quick start
1. Copy `config/config.sample.json` → `config/config.json` and fill in your target (tenant,
   subscription, storage account, file system). `config/config.json` is git‑ignored.
2. Run the prerequisite check: `pwsh ./engine/Assert-Prerequisites.ps1`
3. *(M1)* Run the scan → produces `data/inventory.json`.
4. **Dashboard:** `cd web && npm install && npm run dev` — opens Tab 1 (inventory KPIs + tables). It
   reads `data/inventory.json`; run `npm run generate-sample` first if you just want demo data.
5. *(M3–M5)* Run the analyzer + Copilot assessment → Tab 2 proposition + editable Excel.

See [docs/RUNBOOK.md](docs/RUNBOOK.md) for the full procedure and [PLAN.md](PLAN.md) for the design.

## Portability
This repo is target‑agnostic. Secrets and real values live only in the git‑ignored
`config/config.json` and `data/`. A customer runs the same repo against **their own** environment.

## Repository layout
```
config/    target + auth configuration (config.json is git-ignored)
engine/    PowerShell extractor — Azure-facing, READ-ONLY → data/inventory.json
analyzer/  Node/TS deterministic analysis (offline) → data/analysis.json      (M3)
ai/        Copilot prompt + schema + Excel export/import (user control)        (M4)
web/       Vite + React static dashboard (Tab 1 inventory, Tab 2 proposition)  (M2/M5)
data/      generated artifacts (git-ignored)
docs/      architecture, read-only guarantee, runbook
```

## Status
Phase 1 (assessment). Milestones: **M0 — scaffold + safety** ✅ · **M1 — read‑only scan engine
(`engine/Invoke-Scan.ps1` → `data/inventory.json`)** ✅ (validated on the lab) · **M2 — dashboard
Tab 1 (inventory KPIs + tables)** ✅ *(interactive map in progress)*.
