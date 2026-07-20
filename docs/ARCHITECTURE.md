# Architecture

See [PLAN.md](../PLAN.md) for the full design. This is the condensed view.

## Principle: isolate the credential‑holding, Azure‑facing code
The only component that authenticates and reads from Azure/Entra is a small, auditable, **read‑only**
PowerShell engine. Everything else operates on local JSON files and never touches Azure.

```mermaid
flowchart LR
    subgraph AZ["PowerShell engine — READ-ONLY, Azure-facing"]
        B[Connect: interactive sign-in] --> C[Scan ADLS ACLs + Entra groups/members]
        C --> D[(inventory.json)]
    end
    subgraph OFF["Node / TS — offline"]
        D --> E[Analyzer] --> F[(analysis.json)]
        F --> G[Copilot in GHCP] --> H[(recommendations.json + proposed-model.xlsx)]
        H --> I[User edits Excel] --> J[Importer merges]
    end
    D --> K[Dashboard Tab 1]
    H --> L[Dashboard Tab 2]
    J --> L
```

## Components
- `engine/` — PowerShell extractor (read‑only) → `data/inventory.json`.
- `analyzer/` — Node/TS deterministic analysis → `data/analysis.json`.
- `ai/` — Copilot prompt + schema + Excel export/import (user control).
- `web/` — Vite + React static dashboard (Tab 1 inventory, Tab 2 proposition).
- `config/` — target + auth configuration (`config.json` is git‑ignored).
- `data/` — generated artifacts (git‑ignored).

## Scale
Enumeration is parallel + throttled with checkpoint/resume and streams to JSONL. The dashboard renders
aggregates with drill‑down rather than loading every path at once.
