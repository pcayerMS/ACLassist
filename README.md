# ACLassist — ADLS ACL → RBAC Assessment Tool

A **portable, read‑only** tool that inventories an Azure Data Lake Storage Gen2 (ADLS Gen2)
POSIX‑ACL + Microsoft Entra ID permission structure and uses AI (via GitHub Copilot) to propose a
simplified, RBAC‑style model. Ships as a git repo you clone, point at a target, and run.

> ## 🔒 READ‑ONLY
> This tool **only reads**. It enumerates ACLs, groups, and memberships to build an inventory.
> It will **never** create, modify, move, or delete anything in Azure or Microsoft Entra ID, and it
> performs **no remediation** in Phase 1. See [docs/SECURITY-READONLY.md](docs/SECURITY-READONLY.md).

## What it produces
- **`data/aclassist.db`** — a portable SQLite snapshot of the whole environment (folders, groups, users,
  memberships, group nesting, ACLs, storage roles) plus computed **membership metrics** (effective users per
  group, transitive nested‑group counts, direct vs. effective groups per user). One file, one scan.
- **Tab 1 — Inventory:** loads `aclassist.db` and renders the real ACL/permission structure as filterable,
  sortable, Excel‑exportable tables (Groups, Folders, Users, Group nesting, Memberships, Storage roles) with
  clickable KPI cards that jump straight to the relevant pre‑filtered view.
- **Tab 2 — Proposition:** AI‑generated, fully user‑editable recommendations to consolidate the sprawl
  into an RBAC‑style model, with a before→after map. You approve/modify/reject everything.

## Prerequisites
- **Windows PowerShell 5.1** (built into Windows) or PowerShell 7 — for the scan engine.
- PowerShell modules `Az.Accounts`, `Az.Storage`, `Az.Resources`, `Microsoft.Graph.Authentication`,
  `Microsoft.Graph.Groups`, `Microsoft.Graph.Users` — the checker **auto‑installs** these.
- **SQLite is bundled** (`engine/tools/sqlite3.exe`, public‑domain) — nothing to install; the engine uses it
  locally to build `data/aclassist.db`.
- **The dashboard needs nothing** — it's a single HTML file you open in a browser (SQLite runs in‑page via
  WebAssembly, fully offline).

Run the checker (offers to install any missing modules — current‑user only, no winget/Node):

```powershell
powershell -File ./engine/Assert-Prerequisites.ps1
```

## Quick start
1. **Check prerequisites** (offers to install any missing modules — current‑user only):
   `powershell -File ./engine/Assert-Prerequisites.ps1`
2. **Run the assessment** — one command signs you in, lets you pick subscription / storage account /
   container the first time (saved to the git‑ignored `config/config.json`), performs the read‑only scan,
   and builds the analyzed snapshot `data/aclassist.db`:

   ```powershell
   pwsh -File ./engine/Invoke-Assessment.ps1
   ```

   Auth is interactive OAuth only — no SAS or keys. Sign‑in and read‑only consent are shown before anything
   is read. Re‑runs reuse your saved target; pass `-Reconfigure` to change it, or `-SkipScan` to rebuild the
   database from the last scan.
3. **Open the dashboard:** open `dashboard/ACLassist.html` in any browser and load your `data/aclassist.db`
   (drag‑and‑drop or file picker). Tab 1 shows the inventory KPIs + filterable tables; click a KPI card to
   jump to a pre‑filtered view, and **Export filtered / Export all** to Excel. No install.

### Try it without Azure (synthetic sample)
To see the dashboard before running a live scan, build a sample database from bundled synthetic data:

```powershell
cd web ; npm install ; npm run generate-sample ; cd ..
powershell -File ./engine/Build-SampleDb.ps1     # → data/aclassist.db (no Azure calls)
```

Then open `dashboard/ACLassist.html` and load `data/aclassist.db`.

> **Tab 2 (AI proposition)** is being rebuilt on the new `aclassist.db` data model — see [PLAN.md](PLAN.md)
> (v2‑P2) for the updated proposition pipeline.

See [docs/RUNBOOK.md](docs/RUNBOOK.md) for the full procedure and [PLAN.md](PLAN.md) for the design.

## Portability
This repo is target‑agnostic. Secrets and real values live only in the git‑ignored
`config/config.json` and `data/`. A customer runs the same repo against **their own** environment.

## Repository layout
```
config/       target + auth configuration (config.json is git-ignored)
engine/       PowerShell — Azure-facing, READ-ONLY. Invoke-Assessment.ps1 → data/aclassist.db
engine/sql/   schema.sql + analyze.sql (SQLite build + membership-metric queries)
engine/tools/ bundled sqlite3.exe (public domain) used to build the snapshot
analyzer/     PowerShell offline analysis (legacy JSON path)                          (M3)
ai/           Copilot prompt + schema + Excel export/import (user control)            (M4)
web/          Vite + React dashboard source (build → single self-contained HTML)      (M2/M5)
dashboard/    ACLassist.html — the built single-file dashboard (reads .db via sql.js)
data/         generated artifacts incl. aclassist.db (git-ignored)
docs/         architecture, read-only guarantee, runbook
```

## Status
Phase 1 (assessment). Milestones: **M0 — scaffold + safety** ✅ · **M1 — read‑only scan engine
(built‑in PowerShell 5.1+)** ✅ (validated on the lab) · **M2 — portable single‑file dashboard, Tab 1**
✅ *(interactive map in progress)* **· Phase A** — per‑column filters, Excel export, click‑to‑sort,
clickable KPI cards, and Group‑nesting / Memberships / Storage‑roles sub‑tables ✅ · **M3 — offline
analyzer (`analyzer/Invoke-Analysis.ps1` → `data/analysis.json`)** ✅.

**Behavioural group model** — groups are labelled by *observed function* (access / role / hybrid / unused)
with an effective-access **status** (active / **dormant** / unused), naming-independent so it works for
any customer ✅.

**M4 — AI proposition (GHCP)** — a Copilot prompt (`ai/prompts/assess.prompt.md`) turns `analysis.json`
into a schema-validated `recommendations.json` + an editable `proposed-model.xlsx`
(Approve / Modify / Reject); on the sample it proposes **18 roles** from 2,312 groups (~99%). ✅

**M5 — Proposition (Tab 2)** — the dashboard renders `recommendations.json`: savings cards, a before→after
summary, and the filterable / exportable proposed‑roles table with the Decision column. ✅

**v2 (SQLite data model)** — the engine now emits a single portable **`data/aclassist.db`** built by a
bundled `sqlite3.exe`, and computes **membership metrics** (effective users/group, transitive nested‑group
counts, direct vs. effective groups/user) in SQL. One command — `engine/Invoke-Assessment.ps1` — scans and
analyzes end‑to‑end, and the dashboard reads the `.db` in‑browser via sql.js (WebAssembly). Designed to scale
to deeply nested directories with thousands of groups per user. ✅ *(v2‑P1; proposition on the new model is v2‑P2.)*
