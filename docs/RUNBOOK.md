# Runbook

> Everything here is **read‑only**. See [SECURITY-READONLY.md](SECURITY-READONLY.md).

## 1. Install prerequisites
```powershell
pwsh ./engine/Assert-Prerequisites.ps1
```
Checks PowerShell 7, the required `Az.*` / `Microsoft.Graph.*` modules, and Node.js LTS, and offers to
install anything missing (local installs only). Add `-AssumeYes` to install without prompts.

## 2. Configure the target
Copy the sample and edit it (your copy is git‑ignored):
```powershell
Copy-Item ./config/config.sample.json ./config/config.json
```
Set `target.tenantId`, `target.subscriptionId`, `target.storageAccountName`, `target.fileSystem`.
Choose `auth.mode`:
- `interactive` — you are prompted to sign in (Azure + Microsoft Graph).
- `sas` — paste a **read + list** SAS into `auth.sasToken` for the ADLS data plane (Graph still uses
  interactive read scopes for groups/users).

**Network:** if the storage account uses a private endpoint, run from a host that can reach it
(in‑network / jump host) — e.g. the lab VM via Bastion.

## 3. Confirm read‑only + run the scan  *(M1)*
```powershell
pwsh ./engine/Invoke-Scan.ps1 -ConfigPath ./config/config.json
```
Shows the read‑only consent banner, signs in (or uses the SAS), enumerates folders + ACLs + groups +
memberships + users + existing RBAC, and writes `data/inventory.json` (+ `data/inventory.jsonl`).

**Identity:** the scan reads ACLs across the whole lake, so sign in with an identity that has
data‑plane read everywhere — **Storage Blob Data Reader/Owner** (in the lab, `admin@…`) or a
read+list SAS — plus Microsoft Graph directory read. The lab *guest* only sees the Finance slice, so
use `admin@…` for a full inventory.

**Expected on first run (lab):** the ADLS pass is quick (~390 folders); the Graph pass enumerates
members for ~2,312 groups **one at a time**, which takes several minutes (batching is an M6
optimization). Progress is printed. The container root `/` ACL is intentionally not captured (the
cmdlets can't address it); every non‑root folder ACL is.

## 4. View the inventory — dashboard Tab 1  *(M2)*
```powershell
cd web
npm install          # first time (needs Node.js LTS)
npm run dev          # copies ../data/inventory.json in, then serves the dashboard
```
Open the printed URL. Tab 1 shows KPI cards (folders, groups, users, ACEs, **orphan groups**) and
searchable Folders / Groups / Users / RBAC tables. No scan yet? `npm run generate-sample` creates a demo
inventory. *(The interactive map is the next increment.)*

## 5. Analyze + AI proposition  *(M3–M5)*
Run the analyzer, then the Copilot assessment (`ai/prompts/assess.prompt.md`) to produce
`data/recommendations.json` + `data/proposed-model.xlsx`. Edit the Excel to approve/modify/reject, then
review Tab 2.

---
*M0 delivered the scaffold + safety + prerequisites; **M1 delivers the scan above**. Steps 4–5
(dashboard + AI proposition) arrive in later milestones.*
