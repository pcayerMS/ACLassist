# Copilot instructions — ADLS ACL → RBAC assessment tool

This repository is a **READ‑ONLY** assessment tool. Follow these rules.

## Absolute rules
- **Never** generate or run code that creates, modifies, moves, or deletes anything in Azure or
  Microsoft Entra ID. The engine uses read‑only operations only — see
  [`engine/ReadOnly.Allowlist.psd1`](../engine/ReadOnly.Allowlist.psd1).
- No remediation / "apply" in Phase 1. Proposals are **data only**; the user approves them in Excel.
- Secrets and real target values belong only in the git‑ignored `config/config.json` — never commit them.

## Architecture (data flow)
1. `engine/*` (PowerShell, Azure‑facing, read‑only) → `data/inventory.json`.
2. `analyzer/*` (Node/TS, offline) → `data/analysis.json`.
3. **AI (you, in GHCP)** read inventory + analysis, follow `ai/prompts/assess.prompt.md`, and write
   `data/recommendations.json` (obeying `ai/recommendations.schema.json`) + `data/proposed-model.xlsx`.
4. `web/*` (Vite + React, offline) renders Tab 1 (inventory) and Tab 2 (proposition).

## When asked to run the assessment (Tab 2)
- Read `data/inventory.json` and `data/analysis.json` only. **Do not call Azure.**
- Cluster/name roles, explain rationale, quantify savings, and emit the recommendations artifact +
  editable Excel with `Decision` (Approve/Modify/Reject) columns. Keep the user in control.

## Language / tooling
- Engine: **PowerShell 7** (`Az.*`, `Microsoft.Graph.*`). Analyzer + web: **Node/TypeScript**.
- Keep the engine's dependency surface minimal and auditable.
