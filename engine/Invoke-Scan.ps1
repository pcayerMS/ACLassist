#Requires -Version 7.0
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

if (-not (Show-ReadOnlyConsent -AssumeYes:$AssumeYes)) { return }

$started = Get-Date

$invPath = Resolve-RepoPath ($cfg.output.inventoryPath ?? './data/inventory.json') $repoRoot
$jsonlPath = Resolve-RepoPath ($cfg.output.inventoryJsonlPath ?? './data/inventory.jsonl') $repoRoot
$dataDir = Split-Path -Parent $invPath
if ($dataDir -and -not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

$conn = Connect-ScanTarget -Config $cfg

$acl = Invoke-AclScan -StorageContext $conn.StorageContext -FileSystem $cfg.target.fileSystem `
    -RootPath $cfg.target.rootPath -Config $cfg -AceJsonlPath $jsonlPath

$graph = Invoke-GraphScan -Config $cfg -PrincipalRefs $acl.PrincipalRefs

$counts = Export-Inventory -Config $cfg -AclResult $acl -GraphResult $graph -OutPath $invPath -Connection $conn

$elapsed = (Get-Date) - $started
Write-Host ''
Write-ScanLog OK ("Scan complete in {0:n1}s" -f $elapsed.TotalSeconds)
Write-ScanLog OK ("Inventory : {0}" -f $invPath)
Write-ScanLog OK ("ACE stream: {0}" -f $jsonlPath)
Write-Host ''
$counts | Format-Table -AutoSize | Out-String | Write-Host
