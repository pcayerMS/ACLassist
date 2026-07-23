---
mode: agent
description: Generate the RBAC-style proposition (Tab 2) from the offline analysis. READ-ONLY, data only.
---

# ACLassist — RBAC Proposition (Phase 1, READ-ONLY)

You are producing the **proposition** for the ADLS ACL → RBAC assessment. Work **only** from the local
files listed below. **Do not call Azure or Microsoft Entra. Do not run the scan engine. Change nothing in
any cloud.** This is a data-only proposal that the customer approves / modifies / rejects — there is **no
remediation** in Phase 1.

## Inputs (read these — do not fetch anything else)
- `data/analysis.json` — the offline analyzer output. **Authoritative for all numbers.**
- `data/inventory.json` — the raw inventory (for group names / context only).

If either file is missing, stop and tell the user to run the scan (`engine/Invoke-Scan.ps1`) and the
analyzer (`analyzer/Invoke-Analysis.ps1`) first.

## Task
1. Read `data/analysis.json`. Treat its `proposedRoles`, `savings`, `findings`, `personas`, and
   `duplicateGroupClusters` as ground truth — **do not invent groups and do not change the counts**.
2. For **every** entry in `analysis.json.proposedRoles`, emit one role recommendation:
   - `id` = the `proposedRole` value (e.g. `RBAC_Commercial_Reader`).
   - `displayName` = friendly, `"<scope> — <accessLevel>"` (e.g. `Commercial — Reader`).
   - `scope` = `scope`; `accessLevel` = `accessLevel`.
   - `azureRole` = map the access level to the Azure built-in **data-plane** role:
     `Reader → Storage Blob Data Reader`, `Contributor → Storage Blob Data Contributor`,
     `Owner → Storage Blob Data Owner`.
   - `folderScope` = `"/" + scope`.
   - `replacesGroupCount` = `replacesGroupCount`.
   - `replacesGroupsSample` = up to 5 example names from `inventory.json.groups` whose `displayName`
     starts with `ADLS_<scope>_` (context only).
   - `suggestedMembers` = a short, best-effort list of job titles from `analysis.json.personas` that
     plausibly need this scope. Keep it brief; omit if unclear.
   - `rationale` = one or two plain sentences: what it consolidates and why it is safe.
   - `confidence` = `high` for these mechanical department × access-level roles unless something looks off.
   - `decision` = `""` (empty — the reviewer fills this in).
3. Fill `summary` from `analysis.json.savings`: `currentGroups`, `proposedRoleCount` (= number of roles),
   `groupsEliminated`, `reductionPct`, and a one-line `headline`.
4. Copy `analysis.json.findings` into `findings`.
5. Write the result to `data/recommendations.json`. It **must** validate against
   [`ai/recommendations.schema.json`](../recommendations.schema.json).
6. Build the editable Excel: run `cd web && node scripts/build-proposal-xlsx.mjs`. This writes
   `data/proposed-model.xlsx` with a **Decision (Approve / Modify / Reject)** column.
7. Summarize for the user: the headline savings, the proposed roles, and remind them to review / edit the
   `Decision` column in `data/proposed-model.xlsx`. **Nothing is applied** — remediation is a later phase.

## Guardrails
- All numbers come from `analysis.json`. If your totals don't match its `savings`, fix your output.
- Keep the customer in control: every `decision` starts empty; you only *propose*.
- The output at `data/recommendations.json` must be schema-valid JSON.
- Stay READ-ONLY: no Azure/Entra calls, no writes outside `data/`.
