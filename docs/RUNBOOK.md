# Runbook

> Everything here is **read‑only**. See [SECURITY-READONLY.md](SECURITY-READONLY.md).

## 1. Install prerequisites
Runs on **built‑in Windows PowerShell 5.1** (or PowerShell 7 if you have it). The dashboard needs nothing.
```powershell
powershell -File ./engine/Assert-Prerequisites.ps1   # or: pwsh ./engine/Assert-Prerequisites.ps1
```
Checks the required `Az.*` / `Microsoft.Graph.*` modules and offers to install any that are missing
(current‑user PowerShell modules only — no winget, no Node). Add `-AssumeYes` to install without prompts.

## 2. Configure the target  *(interactive)*
Run the setup — it signs you in, lets you **pick** the target from lists, and writes
`config/config.json` (git‑ignored, local only). Re‑running proposes your previous answers as defaults
(press Enter to keep each one):
```powershell
pwsh -File ./engine/Initialize-Config.ps1     # or: powershell -File ./engine/Initialize-Config.ps1
```
You type your **tenant** and **subscription**, then choose the **storage account** and **container**
from lists (the resource group is derived automatically). Auth is **interactive OAuth only** — no SAS,
no keys, no stored secret; an optional **sign‑in UPN** is remembered as a login hint. Setup also runs
automatically on the first assessment if no config exists; use `Invoke-Assessment.ps1 -Reconfigure` to
change the target later.

**Network:** if the storage account uses a private endpoint, run from a host that can reach it
(in‑network / jump host).

## 3. Confirm read‑only + run the assessment  *(one command)*
```powershell
pwsh -File ./engine/Invoke-Assessment.ps1     # or: powershell -File ./engine/Invoke-Assessment.ps1
```
Shows the read‑only consent banner, signs in, enumerates folders + ACLs + groups + memberships + users +
existing RBAC, then stages the data and builds the analyzed SQLite snapshot **`data/aclassist.db`** (using
the bundled `engine/tools/sqlite3.exe`). One command does the whole inventory. Flags: `-Reconfigure` (change
target), `-SkipScan` (rebuild the DB from the last scan), `-AssumeYes` (no prompts). If no config exists yet,
it launches the setup from step 2 first.

**Identity:** the scan reads ACLs across the whole lake, so sign in with an identity that has
data‑plane read everywhere — **Storage Blob Data Reader/Owner** — plus Microsoft Graph directory read.
An identity scoped to only part of the lake produces a partial inventory.

**Expected on first run (lab):** the ADLS pass is quick (~390 folders); the Graph pass enumerates
members for ~2,312 groups **one at a time**, which takes several minutes (batching is an M6
optimization). Progress is printed. The container root `/` ACL **is** captured too (read via the DFS
REST getAccessControl call).

## 4. View the inventory — dashboard Tab 1  *(M2)*
**No install** — the dashboard is a single self‑contained HTML file. Open it in any browser:
```
dashboard/ACLassist.html
```
Click **Open your aclassist.db** (or drag it in) and pick the `data/aclassist.db` the assessment produced —
the dashboard reads it in‑browser via SQLite/WebAssembly (still fully offline). Tab 1 shows KPI cards
(folders, groups, users, ACEs, **dormant groups**, group nesting, memberships, storage roles) and the
inventory as **Groups / Folders / Users / Group nesting / Memberships / Storage roles** tables. Each table has
**per‑column filters** (text or dropdown), **click‑to‑sort** headers, and **Export filtered / Export all** to
Excel (`.xlsx`). The **Users** table shows **Direct groups** vs **Effective groups** (direct + inherited via
nesting) per user; the **Groups** table shows **Nested** (transitive nested groups) and **Effective users**
per group, and classifies each group by observed function — **Role** (`access` on a folder ACL / `role`
aggregates members / `hybrid` both / `unused` neither, naming‑independent) and **Status** (`active`, or
**`dormant`** = on an ACL but no user is an effective member — a dead grant); the old `ADLS_`/`PRD_` prefix is
kept as the **Naming** label. **Click any KPI card**
to jump to the matching table with the relevant filter pre‑applied (e.g. *Dormant* → Groups filtered to
`status = dormant`); active filters show as chips you can clear. The **Storage roles** tab lists the *existing* Azure role assignments
on the storage account (data‑ vs control‑plane) — a separate system from the folder ACLs, **not** the RBAC
model proposed in Tab 2. Everything runs locally in the browser — nothing is uploaded.

*(Maintainers only — to rebuild the HTML from source: `cd web && npm install && npm run portable`.)*

**Try it without Azure:** to preview the dashboard on synthetic data, run `cd web ; npm run generate-sample`
then `powershell -File ./engine/Build-SampleDb.ps1` (no Azure calls) to produce `data/aclassist.db`, and load
it in step 4.

> **Note — proposition pipeline (steps 5–7) is being migrated.** `Invoke-Assessment.ps1` already analyzes
> everything into `data/aclassist.db`. The steps below are the **legacy JSON path** (they read the separate
> `data/inventory.json` / `analysis.json`) used to generate the AI proposition for Tab 2, which is being
> rebuilt on the `.db` in v2‑P2 — see [PLAN.md](../PLAN.md). To run them today, produce the JSON inventory
> with the legacy `engine/Invoke-Scan.ps1` first.

## 5. Analyze the sprawl  *(M3, legacy JSON path)*
```powershell
powershell -File ./analyzer/Invoke-Analysis.ps1
```
Reads `data/inventory.json` (+ `data/inventory.jsonl`) **offline** and writes `data/analysis.json`:
duplicate‑grant groups, orphan/empty groups, user **personas** (by effective access), a mechanical
role‑collapse model (per department × access level), and **quantified savings**. No Azure, no new install.

## 6. AI proposition  *(M4)*
In VS Code with GitHub Copilot, run the prompt [`ai/prompts/assess.prompt.md`](../ai/prompts/assess.prompt.md).
Copilot reads `data/analysis.json` (READ‑ONLY — no Azure), names each role, maps it to an Azure built‑in
data‑plane role, writes the rationale, and emits `data/recommendations.json` (validated against
`ai/recommendations.schema.json`). It then builds the editable workbook:
```powershell
cd web && node scripts/build-proposal-xlsx.mjs   # -> data/proposed-model.xlsx
```
Open `data/proposed-model.xlsx`, review each proposed role, and set **Decision = Approve / Modify / Reject**.
Nothing is applied — remediation is a later phase.

## 7. View the proposition — dashboard Tab 2  *(M5)*
Open `dashboard/ACLassist.html` (load your `data/inventory.json` first if you haven't), then click the
**2 · Proposition** tab and load your `data/recommendations.json` (drag‑and‑drop or file picker). Tab 2 shows
the savings (groups today → proposed roles, groups retired, % reduction), the **before → after** summary, and
the full **proposed‑roles** table (filter / sort / Excel export). The **Decision** column reflects
`data/recommendations.json`; you make the actual calls in `data/proposed-model.xlsx` (folding those edits back
into the dashboard is a small follow‑up). Everything runs locally — nothing is uploaded, and **nothing is applied**.

---
*M0 scaffold + safety · M1 read‑only scan · M2 dashboard Tab 1 · M3 analyzer · M4 AI proposition · M5 Tab 2 (above).
M4–M5 (AI proposition + Tab 2) are next.*
