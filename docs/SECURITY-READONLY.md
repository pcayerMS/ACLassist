# Read‑only guarantee

**Phase 1 performs no writes.** This tool only *reads* to build an inventory and *propose* a model.
It never creates, modifies, moves, or deletes anything in Azure or Microsoft Entra ID, and it performs
no remediation.

## How it is enforced
1. **Operation allowlist** — the engine may only call the cmdlets in
   [`../engine/ReadOnly.Allowlist.psd1`](../engine/ReadOnly.Allowlist.psd1). All are read/list
   operations (plus client‑side context cmdlets that create only in‑memory objects).
2. **Read‑only permissions** — only Microsoft Graph *read* scopes are requested; an optional ADLS SAS
   is accepted only with **read + list** permissions.
3. **Consent banner** — every run starts with `../engine/Show-ReadOnlyConsent.ps1`, which states the
   tool is read‑only and requires explicit confirmation before anything is accessed.
4. **No apply path** — there is no remediation code in Phase 1. Applying an approved model is a
   separate, opt‑in Phase 2.

## Operations the engine is permitted to perform
| Purpose | Operation | Mutates Azure/Entra? |
|---|---|---|
| Sign in (Azure) | `Connect-AzAccount`, `Get-AzContext`, `Set-AzContext` | No — client context only |
| Sign in (Graph) | `Connect-MgGraph`, `Get-MgContext` | No |
| Build storage context | `New-AzStorageContext` | No — client object only |
| Enumerate folders + ACLs | `Get-AzDataLakeGen2Item`, `Get-AzDataLakeGen2ChildItem` | No — read |
| Capture existing RBAC | `Get-AzRoleAssignment` | No — read |
| Enumerate groups + members | `Get-MgGroup`, `Get-MgGroupMember`, `Get-MgGroupTransitiveMember` | No — read |
| Enumerate users | `Get-MgUser` | No — read |

## Verify it yourself
Search the `engine/` scripts: there are **no** `New-`/`Set-`/`Update-`/`Remove-`/`Add-`/`Move-`
operations against Azure resources, ADLS data, or directory objects. (`New-AzStorageContext` and
`Set-AzContext` create/select **client‑side context objects only** and change nothing remotely; local
file writes such as writing `data/inventory.json` are not Azure/Entra mutations.)
