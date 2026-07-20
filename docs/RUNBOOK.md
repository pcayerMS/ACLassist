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
automatically on the first scan if no config exists; use `Invoke-Scan.ps1 -Reconfigure` to change it later.

**Network:** if the storage account uses a private endpoint, run from a host that can reach it
(in‑network / jump host).

## 3. Confirm read‑only + run the scan  *(M1)*
```powershell
pwsh -File ./engine/Invoke-Scan.ps1        # or: powershell -File ./engine/Invoke-Scan.ps1
```
Shows the read‑only consent banner, signs in, enumerates folders + ACLs + groups +
memberships + users + existing RBAC, and writes `data/inventory.json` (+ `data/inventory.jsonl`).
(If no config exists yet, the scan launches the setup from step 2 first.)

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
Click **Open your inventory.json** (or drag it in) and pick the `data/inventory.json` the scan produced.
Tab 1 shows KPI cards (folders, groups, users, ACEs, **unreachable groups**, group nesting, memberships,
storage roles) and the inventory as **Groups / Folders / Users / Group nesting / Memberships / Storage
roles** tables. Each table has **per‑column filters** (text or dropdown), **click‑to‑sort** headers, and
**Export filtered / Export all** to Excel (`.xlsx`). The **Groups** table classifies each group by observed
function — **Role** (`access` on a folder ACL / `role` aggregates members / `hybrid` both / `unused` neither,
naming‑independent) and **Status** (`active`, or **`unreachable`** = on an ACL but no user is an effective
member — a dead grant); the old `ADLS_`/`PRD_` prefix is kept as the **Naming** label. **Click any KPI card**
to jump to the matching table with the relevant filter pre‑applied (e.g. *Unreachable* → Groups filtered to
`status = unreachable`); active filters show as chips you can clear. The **Storage roles** tab lists the *existing* Azure role assignments
on the storage account (data‑ vs control‑plane) — a separate system from the folder ACLs, **not** the RBAC
model proposed in Tab 2. Everything runs locally in the browser — nothing is uploaded.

*(Maintainers only — to rebuild the HTML from source: `cd web && npm install && npm run portable`.)*

## 5. Analyze the sprawl  *(M3)*
```powershell
powershell -File ./analyzer/Invoke-Analysis.ps1
```
Reads `data/inventory.json` (+ `data/inventory.jsonl`) **offline** and writes `data/analysis.json`:
duplicate‑grant groups, orphan/empty groups, user **personas** (by effective access), a mechanical
role‑collapse model (per department × access level), and **quantified savings**. No Azure, no new install.

## 6. AI proposition  *(M4–M5, next)*
In VS Code + GitHub Copilot, run `ai/prompts/assess.prompt.md` — Copilot reads `analysis.json`, names the
roles, writes the rationale, and produces `data/recommendations.json` + the editable Excel for Tab 2.

---
*M0 scaffold + safety · M1 read‑only scan · M2 single‑file dashboard · M3 offline analyzer (above).
M4–M5 (AI proposition + Tab 2) are next.*
