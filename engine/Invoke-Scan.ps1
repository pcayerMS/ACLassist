#Requires -Version 5.1
<#
.SYNOPSIS
    READ-ONLY assessment scan: enumerates ADLS Gen2 ACLs + Entra groups/members/users and writes a
    normalized inventory snapshot. Creates, modifies, or deletes NOTHING in Azure or Entra.

.DESCRIPTION
    Orchestrates the M1 pipeline:
      1. Load config + show the read-only consent banner.
      2. Connect (interactive sign-in, or SAS for the ADLS data plane).
      3. Scan ADLS folders + ACLs  -> streams ACE records to data/inventory.jsonl.
      4. Scan Entra groups + members + users + existing RBAC.
      5. Assemble data/inventory.json.

.PARAMETER ConfigPath
    Path to config.json. Defaults to ../config/config.json relative to this script.

.PARAMETER AssumeYes
    Skip the interactive consent prompt (the banner is still shown).

.EXAMPLE
    pwsh ./engine/Invoke-Scan.ps1 -ConfigPath ./config/config.json
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$AssumeYes
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here

. "$here/lib/Common.ps1"
. "$here/lib/Connect-Target.ps1"
. "$here/lib/Invoke-AclScan.ps1"
. "$here/lib/Invoke-GraphScan.ps1"
. "$here/lib/Export-Inventory.ps1"
. "$here/Show-ReadOnlyConsent.ps1"

if (-not $ConfigPath) { $ConfigPath = Join-Path $repoRoot 'config/config.json' }
$cfg = Get-ScanConfig -Path $ConfigPath

Assert-EngineModules   # fail early + clearly if Az/Graph modules are missing for this PowerShell edition

Write-Host ''
Write-Host ('Target : {0} / {1}' -f $cfg.target.storageAccountName, $cfg.target.fileSystem) -ForegroundColor Cyan
Write-Host ('Sub    : {0}   Tenant: {1}' -f $cfg.target.subscriptionId, $cfg.target.tenantId) -ForegroundColor Cyan

if (-not (Show-ReadOnlyConsent -AssumeYes:$AssumeYes)) { return }

$started = Get-Date

$invRel = if ($cfg.output.inventoryPath) { $cfg.output.inventoryPath } else { './data/inventory.json' }
$jsonlRel = if ($cfg.output.inventoryJsonlPath) { $cfg.output.inventoryJsonlPath } else { './data/inventory.jsonl' }
$invPath = Resolve-RepoPath $invRel $repoRoot
$jsonlPath = Resolve-RepoPath $jsonlRel $repoRoot
$dataDir = Split-Path -Parent $invPath
if ($dataDir -and -not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

$conn = Connect-ScanTarget -Config $cfg

$acl = Invoke-AclScan -Config $cfg -AceJsonlPath $jsonlPath

$graph = Invoke-GraphScan -Config $cfg -PrincipalRefs $acl.PrincipalRefs

$counts = Export-Inventory -Config $cfg -AclResult $acl -GraphResult $graph -OutPath $invPath -Connection $conn

$elapsed = (Get-Date) - $started
Write-Host ''
Write-ScanLog OK ("Scan complete in {0:n1}s" -f $elapsed.TotalSeconds)
Write-ScanLog OK ("Inventory : {0}" -f $invPath)
Write-ScanLog OK ("ACE stream: {0}" -f $jsonlPath)
Write-Host ''
$counts | Format-Table -AutoSize | Out-String | Write-Host
