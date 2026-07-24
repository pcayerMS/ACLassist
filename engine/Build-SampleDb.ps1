#Requires -Version 5.1
<#
.SYNOPSIS
    DEV/TEST helper — builds data/aclassist.db from the synthetic sample (no Azure), so the dashboard can
    be tested without a live scan. The real pipeline is engine/Invoke-Assessment.ps1.
.DESCRIPTION
    Reads the sample data/inventory.json (+ inventory.jsonl) produced by `npm run generate-sample`,
    stages it as CSV, and builds/analyzes data/aclassist.db using the same schema + SQL as the engine.
#>
[CmdletBinding()]
param([string]$InventoryPath, [string]$AceJsonlPath, [string]$OutDbPath)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
. "$here/lib/SqliteDb.ps1"

if (-not $InventoryPath) { $InventoryPath = Join-Path $repoRoot 'data/inventory.json' }
if (-not $AceJsonlPath) { $AceJsonlPath = Join-Path $repoRoot 'data/inventory.jsonl' }
if (-not $OutDbPath) { $OutDbPath = Join-Path $repoRoot 'data/aclassist.db' }

if (-not (Test-Path $InventoryPath)) {
    throw "Sample not found: $InventoryPath`nRun:  cd web ; npm run generate-sample   (then re-run this script)."
}

$sqlite = Resolve-Sqlite3Path -Config $null -RepoRoot $repoRoot
$inv = Get-Content $InventoryPath -Raw | ConvertFrom-Json
$staging = Join-Path (Split-Path -Parent $OutDbPath) 'staging'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

Write-AclCsv -Path (Join-Path $staging 'groups.csv') -Columns @('id', 'display_name', 'description', 'kind', 'security_enabled', 'mail') -Rows (
    $inv.groups | ForEach-Object { [pscustomobject]@{ id = $_.id; display_name = $_.displayName; description = $_.description; kind = $_.kind; security_enabled = [int][bool]$_.securityEnabled; mail = $_.mail } })
Write-AclCsv -Path (Join-Path $staging 'users.csv') -Columns @('id', 'upn', 'display_name', 'job_title', 'account_enabled') -Rows (
    $inv.users | ForEach-Object { [pscustomobject]@{ id = $_.id; upn = $_.upn; display_name = $_.displayName; job_title = $_.jobTitle; account_enabled = [int][bool]$_.accountEnabled } })
Write-AclCsv -Path (Join-Path $staging 'memberships.csv') -Columns @('group_id', 'member_id', 'member_type') -Rows (
    $inv.memberships | ForEach-Object { [pscustomobject]@{ group_id = $_.groupId; member_id = $_.memberId; member_type = $_.memberType } })
Write-AclCsv -Path (Join-Path $staging 'nesting.csv') -Columns @('parent_group_id', 'child_group_id') -Rows (
    $inv.groupNesting | ForEach-Object { [pscustomobject]@{ parent_group_id = $_.parentGroupId; child_group_id = $_.childGroupId } })
Write-AclCsv -Path (Join-Path $staging 'folders.csv') -Columns @('id', 'path', 'name', 'depth', 'level1', 'level2', 'level3', 'level4', 'base_permissions') -Rows (
    $inv.folders | ForEach-Object { [pscustomobject]@{ id = $_.id; path = $_.path; name = $_.name; depth = $_.depth; level1 = $_.level1; level2 = $_.level2; level3 = $_.level3; level4 = $_.level4; base_permissions = $_.basePermissions } })
Write-AclCsv -Path (Join-Path $staging 'rbac.csv') -Columns @('principal_id', 'principal_type', 'role_definition_name', 'scope') -Rows (
    $inv.rbacAssignments | ForEach-Object { [pscustomobject]@{ principal_id = $_.principalId; principal_type = $_.principalType; role_definition_name = $_.roleDefinitionName; scope = $_.scope } })
$aceRows = @()
if (Test-Path $AceJsonlPath) {
    $aceRows = Get-Content $AceJsonlPath | Where-Object { $_ } | ForEach-Object { $o = $_ | ConvertFrom-Json; [pscustomobject]@{ folder_id = $o.folderId; folder_path = $o.folderPath; principal_id = $o.principalId; principal_type = $o.principalType; scope = $o.scope; permissions = $o.permissions; is_named = [int][bool]$o.isNamed } }
}
Write-AclCsv -Path (Join-Path $staging 'aces.csv') -Columns @('folder_id', 'folder_path', 'principal_id', 'principal_type', 'scope', 'permissions', 'is_named') -Rows $aceRows
$t = $inv.meta.target
Write-AclCsv -Path (Join-Path $staging 'meta.csv') -Columns @('key', 'value') -Rows @(
    [pscustomobject]@{ key = 'scanId'; value = [guid]::NewGuid().ToString() }
    [pscustomobject]@{ key = 'generatedUtc'; value = (Get-Date).ToUniversalTime().ToString('o') }
    [pscustomobject]@{ key = 'tool'; value = 'aclassist-sample' }
    [pscustomobject]@{ key = 'storageAccount'; value = $t.storageAccount }
    [pscustomobject]@{ key = 'fileSystem'; value = $t.fileSystem }
    [pscustomobject]@{ key = 'rootPath'; value = $t.rootPath })

New-AclDatabase -Sqlite $sqlite -DbPath $OutDbPath -SchemaSqlPath "$here/sql/schema.sql"
Import-AclCsvs -Sqlite $sqlite -DbPath $OutDbPath -StagingDir $staging -Tables @('folders', 'groups', 'users', 'memberships', 'nesting', 'aces', 'rbac', 'meta')
Invoke-AclAnalysis -Sqlite $sqlite -DbPath $OutDbPath -AnalyzeSqlPath "$here/sql/analyze.sql"
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

$snap = Get-AclQuery -Sqlite $sqlite -DbPath $OutDbPath -Sql 'SELECT total_groups, total_users, access_groups, role_groups, dormant_groups, avg_groups_per_user, max_groups_per_user FROM snapshots ORDER BY rowid DESC LIMIT 1'
Write-Host ("[sample-db] wrote {0} ({1:n0} bytes)" -f $OutDbPath, (Get-Item $OutDbPath).Length) -ForegroundColor Green
$snap | Format-List | Out-String | Write-Host
