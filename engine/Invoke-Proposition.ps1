#Requires -Version 5.1
<#
.SYNOPSIS
    Builds the deterministic RBAC proposition inside data/aclassist.db. OFFLINE — no Azure, no AI.
.DESCRIPTION
    Reads the analyzed assessment database and computes the proposed model with all five reduction levers:
    RBAC-style roles, retire dormant/unused groups, merge duplicate groups, flatten pass-through nesting,
    and flag users carrying too many groups.

    Every number is produced by engine/sql/propose.sql — reproducible SQL, nothing inferred. The optional
    AI naming step (ai/prompts/propose.prompt.md) may afterwards improve display names and rationale only;
    it can never change a count.

    Nothing is applied anywhere. This writes proposal tables into the local database for review.
.EXAMPLE
    pwsh -File ./engine/Invoke-Proposition.ps1
.EXAMPLE
    pwsh -File ./engine/Invoke-Proposition.ps1 -DbPath D:\lab\aclassist.db -OverMembershipThreshold 100
#>
[CmdletBinding()]
param(
    [string]$DbPath,
    [string]$ConfigPath,
    [ValidateRange(1, 100000)][int]$OverMembershipThreshold = 50
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
. "$here/lib/SqliteDb.ps1"

if (-not $DbPath) { $DbPath = Join-Path $repoRoot 'data/aclassist.db' }
if (-not (Test-Path $DbPath)) {
    throw "No assessment database at $DbPath`nRun the scan first:  pwsh -File ./engine/Invoke-Assessment.ps1"
}

$cfg = $null
if ($ConfigPath -and (Test-Path $ConfigPath)) { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json }
$sqlite = Resolve-Sqlite3Path -Config $cfg -RepoRoot $repoRoot

# group_concat(... ORDER BY ...) — used to build a canonical grant footprint — needs SQLite 3.44+.
$ver = ((Invoke-SqliteText -Sqlite $sqlite -DbPath $DbPath -Sql 'SELECT sqlite_version();') -join '').Trim()
$parts = $ver -split '\.'
if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 44)) {
    throw "sqlite3 $ver is too old (need 3.44+ for deterministic footprint ordering). Use the bundled engine/tools/sqlite3.exe."
}

# The analysis tables must already exist, otherwise the proposal would be built on nothing.
$hasAnalysis = (Invoke-SqliteText -Sqlite $sqlite -DbPath $DbPath `
        -Sql "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='group_metrics';") -join ''
if ($hasAnalysis.Trim() -eq '0') {
    throw "Database has no analysis tables. Re-run:  pwsh -File ./engine/Invoke-Assessment.ps1 -SkipScan"
}

Write-Host ''
Write-Host 'ACLassist — proposition (offline, read-only, nothing is applied)' -ForegroundColor Cyan
Write-Host ("Database : {0}" -f $DbPath) -ForegroundColor Cyan
Write-Host ("SQLite   : {0}" -f $ver) -ForegroundColor Cyan

# Parameters travel through a table, never string-built into SQL.
[void](Invoke-SqliteText -Sqlite $sqlite -DbPath $DbPath -Sql @'
CREATE TABLE IF NOT EXISTS proposal_config (key TEXT PRIMARY KEY, value TEXT);
DELETE FROM proposal_config;
'@)

$staging = Join-Path (Split-Path -Parent $DbPath) 'staging'
Write-AclCsv -Path (Join-Path $staging 'proposal_config.csv') -Columns @('key', 'value') -Rows @(
    [pscustomobject]@{ key = 'overMembershipThreshold'; value = $OverMembershipThreshold }
    [pscustomobject]@{ key = 'generatedUtc'; value = (Get-Date).ToUniversalTime().ToString('o') }
    [pscustomobject]@{ key = 'engine'; value = 'aclassist-propose-v2' })
Import-AclCsvs -Sqlite $sqlite -DbPath $DbPath -StagingDir $staging -Tables @('proposal_config')
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

Invoke-AclAnalysis -Sqlite $sqlite -DbPath $DbPath -AnalyzeSqlPath (Join-Path $here 'sql/propose.sql')

$s = Get-AclQuery -Sqlite $sqlite -DbPath $DbPath -Sql 'SELECT * FROM proposal_summary;'
if ($s -is [array]) { $s = $s[0] }

Write-Host ''
Write-Host ('Groups today            : {0}' -f $s.current_groups)
Write-Host ''
Write-Host 'Access-safe reduction (no user loses or gains access)' -ForegroundColor Green
Write-Host ('  retire dormant        : {0}' -f $s.retire_dormant)
Write-Host ('  retire unused         : {0}' -f $s.retire_unused)
Write-Host ('  merge duplicates      : {0}' -f $s.merge_duplicate)
Write-Host ('  flatten pass-through  : {0}' -f $s.flatten_nesting)
Write-Host ('  -> removable          : {0}  ({1}%)   groups left: {2}' -f $s.safe_removable, $s.safe_reduction_pct, $s.groups_after_safe) -ForegroundColor Green
Write-Host ''
Write-Host 'Full consolidation (adds RBAC roles — review the widening flags)' -ForegroundColor Yellow
Write-Host ('  proposed roles        : {0}   (needing review: {1})' -f $s.proposed_role_count, $s.roles_needing_review)
Write-Host ('  groups mapped to role : {0}' -f $s.map_to_role)
Write-Host ('  kept as-is            : {0}' -f $s.keep_group)
Write-Host ('  -> model size         : {0}  ({1}% fewer)' -f $s.groups_after_full, $s.full_reduction_pct) -ForegroundColor Yellow
Write-Host ''
Write-Host ('Users above {0} effective groups : {1}' -f $OverMembershipThreshold, $s.users_over_threshold)
Write-Host ''
Write-Host 'Nothing was applied. Open dashboard/ACLassist.html -> Tab 2 to review.' -ForegroundColor Cyan
Write-Host ''
