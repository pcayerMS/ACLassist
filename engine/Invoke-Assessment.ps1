#Requires -Version 5.1
<#
.SYNOPSIS
    READ-ONLY ADLS ACL assessment — ONE command. Scans ADLS Gen2 ACLs + Entra
    groups/members/nesting/users/RBAC and builds a SQLite database (scan + analysis in a single pass).
    Creates, modifies, or deletes NOTHING in Azure or Entra.

.DESCRIPTION
    1. Load config + show the read-only consent banner (auto-runs interactive setup if needed).
    2. Connect (interactive sign-in).
    3. Scan ADLS folders + ACLs and Entra groups/members/users/RBAC (read-only).
    4. Stage the results as typed CSV, bulk-load them into data/aclassist.db, and run the deterministic
       analysis SQL (membership metrics, roles/status, savings inputs, history snapshot) — all in SQLite.

.PARAMETER ConfigPath   Path to config.json. Defaults to ../config/config.json.
.PARAMETER AssumeYes    Skip the interactive consent prompt (the banner is still shown).
.PARAMETER Reconfigure  Re-run the interactive setup before scanning.
.PARAMETER SkipScan     Re-run only the analysis SQL over the existing database (no Azure calls).

.EXAMPLE
    pwsh ./engine/Invoke-Assessment.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$AssumeYes,
    [switch]$Reconfigure,
    [switch]$SkipScan
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here

. "$here/lib/Common.ps1"
. "$here/lib/Connect-Target.ps1"
. "$here/lib/Invoke-AclScan.ps1"
. "$here/lib/Invoke-GraphScan.ps1"
. "$here/lib/SqliteDb.ps1"
. "$here/Show-ReadOnlyConsent.ps1"

if (-not $ConfigPath) { $ConfigPath = Join-Path $repoRoot 'config/config.json' }

if (-not $SkipScan) {
    Assert-EngineModules   # fail early + clearly if Az/Graph modules are missing for this edition
    if ($Reconfigure -or -not (Test-ScanConfigComplete -Path $ConfigPath)) {
        if ($Reconfigure) { Write-Host 'Reconfiguring target...' -ForegroundColor Cyan }
        else { Write-Host 'No complete config/config.json found - starting interactive setup...' -ForegroundColor Cyan }
        & (Join-Path $here 'Initialize-Config.ps1') -ConfigPath $ConfigPath
    }
}
$cfg = Get-ScanConfig -Path $ConfigPath
$sqlite = Resolve-Sqlite3Path -Config $cfg -RepoRoot $repoRoot

$dbRel = if ($cfg.output.databasePath) { $cfg.output.databasePath } else { './data/aclassist.db' }
$dbPath = Resolve-RepoPath $dbRel $repoRoot
$dataDir = Split-Path -Parent $dbPath
if ($dataDir -and -not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

if ($SkipScan) {
    if (-not (Test-Path $dbPath)) { throw "No database at $dbPath — run without -SkipScan first." }
    Write-ScanLog OK 'Re-running analysis only (-SkipScan)'
    Invoke-AclAnalysis -Sqlite $sqlite -DbPath $dbPath -AnalyzeSqlPath (Join-Path $here 'sql/analyze.sql')
    Write-ScanLog OK ("Analysis refreshed: {0}" -f $dbPath)
    return
}

Write-Host ''
Write-Host ('Target : {0} / {1}' -f $cfg.target.storageAccountName, $cfg.target.fileSystem) -ForegroundColor Cyan
Write-Host ('Sub    : {0}   Tenant: {1}' -f $cfg.target.subscriptionId, $cfg.target.tenantId) -ForegroundColor Cyan
if (-not (Show-ReadOnlyConsent -AssumeYes:$AssumeYes)) { return }

$started = Get-Date
$staging = Join-Path $dataDir 'staging'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

# --- read-only scan ---
$conn = Connect-ScanTarget -Config $cfg
$acePath = Join-Path $staging 'aces.jsonl'
$acl = Invoke-AclScan -Config $cfg -AceJsonlPath $acePath
$graph = Invoke-GraphScan -Config $cfg -PrincipalRefs $acl.PrincipalRefs

# --- stage as typed CSV (columns in schema order) ---
Write-ScanLog OK 'Staging results as CSV'
Write-AclCsv -Path (Join-Path $staging 'folders.csv') -Columns @('id', 'path', 'name', 'depth', 'level1', 'level2', 'level3', 'level4', 'base_permissions') -Rows (
    $acl.Folders | ForEach-Object { [pscustomobject]@{ id = $_.id; path = $_.path; name = $_.name; depth = $_.depth; level1 = $_.level1; level2 = $_.level2; level3 = $_.level3; level4 = $_.level4; base_permissions = $_.basePermissions } })
Write-AclCsv -Path (Join-Path $staging 'groups.csv') -Columns @('id', 'display_name', 'description', 'kind', 'security_enabled', 'mail') -Rows (
    $graph.Groups | ForEach-Object { [pscustomobject]@{ id = $_.Id; display_name = $_.DisplayName; description = $_.Description; kind = (Get-GroupKind $_.DisplayName $cfg); security_enabled = [int][bool]$_.SecurityEnabled; mail = $_.Mail } })
Write-AclCsv -Path (Join-Path $staging 'users.csv') -Columns @('id', 'upn', 'display_name', 'job_title', 'account_enabled') -Rows (
    $graph.Users | ForEach-Object { [pscustomobject]@{ id = $_.id; upn = $_.upn; display_name = $_.displayName; job_title = $_.jobTitle; account_enabled = [int][bool]$_.accountEnabled } })
Write-AclCsv -Path (Join-Path $staging 'memberships.csv') -Columns @('group_id', 'member_id', 'member_type') -Rows (
    $graph.Memberships | ForEach-Object { [pscustomobject]@{ group_id = $_.groupId; member_id = $_.memberId; member_type = $_.memberType } })
Write-AclCsv -Path (Join-Path $staging 'nesting.csv') -Columns @('parent_group_id', 'child_group_id') -Rows (
    $graph.Nesting | ForEach-Object { [pscustomobject]@{ parent_group_id = $_.parentGroupId; child_group_id = $_.childGroupId } })
Write-AclCsv -Path (Join-Path $staging 'rbac.csv') -Columns @('principal_id', 'principal_type', 'role_definition_name', 'scope') -Rows (
    $graph.Rbac | ForEach-Object { [pscustomobject]@{ principal_id = $_.principalId; principal_type = $_.principalType; role_definition_name = $_.roleDefinitionName; scope = $_.scope } })
$aceRows = Get-Content $acePath | Where-Object { $_ } | ForEach-Object { $o = $_ | ConvertFrom-Json; [pscustomobject]@{ folder_id = $o.folderId; folder_path = $o.folderPath; principal_id = $o.principalId; principal_type = $o.principalType; scope = $o.scope; permissions = $o.permissions; is_named = [int][bool]$o.isNamed } }
Write-AclCsv -Path (Join-Path $staging 'aces.csv') -Columns @('folder_id', 'folder_path', 'principal_id', 'principal_type', 'scope', 'permissions', 'is_named') -Rows $aceRows
$t = $cfg.target
Write-AclCsv -Path (Join-Path $staging 'meta.csv') -Columns @('key', 'value') -Rows @(
    [pscustomobject]@{ key = 'scanId'; value = [guid]::NewGuid().ToString() }
    [pscustomobject]@{ key = 'generatedUtc'; value = (Get-Date).ToUniversalTime().ToString('o') }
    [pscustomobject]@{ key = 'tool'; value = 'aclassist' }
    [pscustomobject]@{ key = 'tenantId'; value = $t.tenantId }
    [pscustomobject]@{ key = 'subscriptionId'; value = $t.subscriptionId }
    [pscustomobject]@{ key = 'storageAccount'; value = $t.storageAccountName }
    [pscustomobject]@{ key = 'fileSystem'; value = $t.fileSystem }
    [pscustomobject]@{ key = 'rootPath'; value = $t.rootPath }
    [pscustomobject]@{ key = 'account'; value = $conn.Account })

# --- build + analyze the database (single pass, all in SQLite) ---
Write-ScanLog OK ('Building database: {0}' -f $dbPath)
New-AclDatabase -Sqlite $sqlite -DbPath $dbPath -SchemaSqlPath (Join-Path $here 'sql/schema.sql')
Import-AclCsvs -Sqlite $sqlite -DbPath $dbPath -StagingDir $staging -Tables @('folders', 'groups', 'users', 'memberships', 'nesting', 'aces', 'rbac', 'meta')
Invoke-AclAnalysis -Sqlite $sqlite -DbPath $dbPath -AnalyzeSqlPath (Join-Path $here 'sql/analyze.sql')
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

$elapsed = (Get-Date) - $started
Write-Host ''
Write-ScanLog OK ("Assessment complete in {0:n1}s" -f $elapsed.TotalSeconds)
Write-ScanLog OK ("Database : {0}" -f $dbPath)
Write-Host ''
$snap = Get-AclQuery -Sqlite $sqlite -DbPath $dbPath -Sql 'SELECT total_folders, total_groups, total_users, access_groups, role_groups, dormant_groups, avg_groups_per_user, max_groups_per_user FROM snapshots ORDER BY rowid DESC LIMIT 1'
$snap | Format-List | Out-String | Write-Host
Write-Host 'Open dashboard/ACLassist.html and load this .db to review.' -ForegroundColor Green
