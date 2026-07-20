# Air Canada — ADLS ACL → RBAC Assessment Tool

A **portable, read‑only** tool that inventories an Azure Data Lake Storage Gen2 (ADLS Gen2)
POSIX‑ACL + Microsoft Entra ID permission structure and uses AI (via GitHub Copilot) to propose a
simplified, RBAC‑style model. Ships as a git repo you clone, point at a target, and run.

> ## 🔒 READ‑ONLY
> This tool **only reads**. It enumerates ACLs, groups, and memberships to build an inventory.
> It will **never** create, modify, move, or delete anything in Azure or Microsoft Entra ID, and it
> performs **no remediation** in Phase 1. See [docs/SECURITY-READONLY.md](docs/SECURITY-READONLY.md).

## What it produces
- **Tab 1 — Inventory:** the real ACL/permission structure as filterable, sortable, Excel‑exportable
  tables (Groups, Folders, Users, Group nesting, Memberships, Storage roles) with clickable KPI cards that
  jump straight to the relevant pre‑filtered view. *(Interactive map next.)*
- **Tab 2 — Proposition:** AI‑generated, fully user‑editable recommendations to consolidate the sprawl
  into an RBAC‑style model, with a before→after map. You approve/modify/reject everything.

## Prerequisites
- **Windows PowerShell 5.1** (built into Windows) or PowerShell 7 — for the scan engine.
- PowerShell modules `Az.Accounts`, `Az.Storage`, `Az.Resources`, `Microsoft.Graph.Authentication`,
  `Microsoft.Graph.Groups`, `Microsoft.Graph.Users` — the checker **auto‑installs** these.
- **The dashboard needs nothing** — it's a single HTML file you open in a browser.

Run the checker (offers to install any missing modules — current‑user only, no winget/Node):

```powershell
powershell -File ./engine/Assert-Prerequisites.ps1
```

## Quick start
1. Run the prerequisite check (offers to install any missing modules):
   `powershell -File ./engine/Assert-Prerequisites.ps1`
2. **Configure the target** — interactive setup signs you in, lets you pick subscription / storage
   account / container from lists, and writes the git‑ignored `config/config.json` (re‑runs propose your
   previous answers as defaults): `pwsh -File ./engine/Initialize-Config.ps1`
3. *(M1)* Run the scan → produces `data/inventory.json`: `pwsh -File ./engine/Invoke-Scan.ps1`
   *(auth is interactive OAuth only — no SAS or keys; if no config exists, the scan launches setup first.)*
4. **Dashboard:** open `dashboard/ACLassist.html` in any browser and load your `data/inventory.json`
   (drag‑and‑drop or file picker) — Tab 1 shows the inventory KPIs + filterable tables; click a KPI card
   to jump to a pre‑filtered view, and **Export filtered / Export all** to Excel. No install.
5. **Analyze:** `powershell -File ./analyzer/Invoke-Analysis.ps1` → `data/analysis.json` (duplicate
   groups, personas, role‑collapse model, quantified savings).
6. *(M4–M5)* Run the Copilot assessment → Tab 2 proposition + editable Excel.

See [docs/RUNBOOK.md](docs/RUNBOOK.md) for the full procedure and [PLAN.md](PLAN.md) for the design.

## Portability
This repo is target‑agnostic. Secrets and real values live only in the git‑ignored
`config/config.json` and `data/`. A customer runs the same repo against **their own** environment.

## Repository layout
```
config/     target + auth configuration (config.json is git-ignored)
engine/     PowerShell extractor — Azure-facing, READ-ONLY → data/inventory.json      (M1)
analyzer/   PowerShell offline analysis → data/analysis.json                          (M3)
ai/         Copilot prompt + schema + Excel export/import (user control)              (M4)
web/        Vite + React dashboard source (build → single self-contained HTML)        (M2/M5)
dashboard/  ACLassist.html — the built, ready-to-open single-file dashboard
data/       generated artifacts (git-ignored)
docs/       architecture, read-only guarantee, runbook
```

## Status
Phase 1 (assessment). Milestones: **M0 — scaffold + safety** ✅ · **M1 — read‑only scan engine
(built‑in PowerShell 5.1+)** ✅ (validated on the lab) · **M2 — portable single‑file dashboard, Tab 1**
✅ *(interactive map in progress)* **· Phase A** — per‑column filters, Excel export, click‑to‑sort,
clickable KPI cards, and Group‑nesting / Memberships / Storage‑roles sub‑tables ✅ · **M3 — offline
analyzer (`analyzer/Invoke-Analysis.ps1` → `data/analysis.json`)** ✅.

**Behavioural group model** — groups are labelled by *observed function* (access / role / hybrid / unused)
with an effective-access **status** (active / **unreachable** / unused), naming-independent so it works for
any customer ✅.
