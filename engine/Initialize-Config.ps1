#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive, READ-ONLY setup for the ADLS ACL assessment. Prompts for the target (tenant,
    subscription, storage account, container) and writes config/config.json.

.DESCRIPTION
    - Re-proposes previously saved values as defaults (press Enter to keep each one).
    - Signs in interactively (no stored secret) and lets you PICK the storage account and container
      from lists, auto-deriving the resource group from the chosen account.
    - Writes config/config.json LOCALLY only. That file is git-ignored and is never committed.
    Creates, modifies, or deletes NOTHING in Azure or Entra - it only reads to populate the pickers.

.PARAMETER ConfigPath
    Where to write config.json. Default: <repo>/config/config.json

.EXAMPLE
    pwsh -File ./engine/Initialize-Config.ps1
#>
[CmdletBinding()]
param([string]$ConfigPath)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
. "$here/lib/Common.ps1"

if (-not $ConfigPath) { $ConfigPath = Join-Path $repoRoot 'config/config.json' }
$samplePath = Join-Path $repoRoot 'config/config.sample.json'

$existing = $null
if (Test-Path $ConfigPath) { try { $existing = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { $existing = $null } }
$template = $null
if (Test-Path $samplePath) { try { $template = Get-Content $samplePath -Raw | ConvertFrom-Json } catch { $template = $null } }

function Get-Prop {
    param($Obj, [string]$Path, $Default)
    $cur = $Obj
    foreach ($p in $Path.Split('.')) {
        if ($null -eq $cur) { return $Default }
        $cur = $cur.$p
    }
    if ($null -eq $cur -or "$cur" -eq '' -or "$cur".StartsWith('<')) { return $Default }
    return $cur
}
function Read-Default {
    param([string]$Prompt, $Default)
    if ($Default) { $answer = Read-Host ("{0} [{1}]" -f $Prompt, $Default) }
    else { $answer = Read-Host $Prompt }
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}
function Select-FromList {
    param([string]$Title, $Items, [scriptblock]$LabelFn, $CurrentValue)
    $arr = @($Items)
    if ($arr.Count -eq 0) { return $null }
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    $default = 1
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $label = & $LabelFn $arr[$i]
        $mark = ''
        if ($CurrentValue -and $label -like "*$CurrentValue*") { $mark = '   <- current'; $default = $i + 1 }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $label, $mark)
    }
    $answer = Read-Host ("Choose 1-{0} [{1}]" -f $arr.Count, $default)
    if ([string]::IsNullOrWhiteSpace($answer)) { return $arr[$default - 1] }
    $idx = 0
    if ([int]::TryParse($answer, [ref]$idx) -and $idx -ge 1 -and $idx -le $arr.Count) { return $arr[$idx - 1] }
    Write-Host 'Invalid choice; using the first entry.' -ForegroundColor Yellow
    return $arr[0]
}

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '  ACLassist setup - configure your target (READ-ONLY assessment)' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '  Press Enter to keep the [previous] value.'
Write-Host '  Saved locally to config/config.json (git-ignored - never committed).'
Write-Host ''

foreach ($m in 'Az.Accounts', 'Az.Storage') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "Module '$m' is not installed for this PowerShell edition. Run  ./engine/Assert-Prerequisites.ps1  first (or use pwsh)."
    }
}
Import-Module Az.Accounts -ErrorAction Stop | Out-Null
Import-Module Az.Storage -ErrorAction Stop | Out-Null

# --- 1) tenant + optional sign-in UPN + subscription (typed) ---
$tenant = Read-Default 'Entra tenant (GUID or domain, e.g. contoso.onmicrosoft.com)' (Get-Prop $existing 'target.tenantId' $null)
if (-not $tenant) { throw 'Tenant is required.' }
$loginHint = Read-Default 'Sign-in UPN to use (optional - Enter to choose at sign-in)' (Get-Prop $existing 'auth.loginHint' $null)
$subInput = Read-Default 'Subscription (GUID or name)' (Get-Prop $existing 'target.subscriptionId' $null)

# --- 2) interactive sign-in (no stored secret) ---
Write-Host ''
Write-ScanLog INFO 'Signing in to Azure (interactive, read-only)...'
$connParams = @{ Tenant = $tenant; ErrorAction = 'Stop' }
if ($loginHint) { $connParams['AccountId'] = $loginHint }
$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $ctx) { Connect-AzAccount @connParams | Out-Null }
try {
    if ($subInput) { Set-AzContext -Subscription $subInput -Tenant $tenant -ErrorAction Stop | Out-Null }
}
catch {
    Connect-AzAccount @connParams | Out-Null
    if ($subInput) { Set-AzContext -Subscription $subInput -ErrorAction Stop | Out-Null }
}
$ctx = Get-AzContext
$subscriptionId = $ctx.Subscription.Id
$tenantId = $ctx.Tenant.Id
if (-not $loginHint) { $loginHint = $ctx.Account.Id }
Write-ScanLog OK ("Signed in as {0}  (sub {1})" -f $ctx.Account.Id, $subscriptionId)

# --- 3) pick the storage account (ADLS Gen2), auto-derive the resource group ---
Write-ScanLog INFO 'Listing storage accounts in the subscription...'
$curAcct = Get-Prop $existing 'target.storageAccountName' $null
$storageAccountName = $null
$resourceGroupName = $null
try {
    $accts = @(Get-AzStorageAccount -ErrorAction Stop)
    $adls = @($accts | Where-Object { $_.EnableHierarchicalNamespace })
    $pickFrom = if ($adls.Count -gt 0) { $adls } else { $accts }
    if ($pickFrom.Count -gt 0) {
        $title = if ($adls.Count -gt 0) { 'ADLS Gen2 storage accounts (hierarchical namespace):' } else { 'Storage accounts:' }
        $sa = Select-FromList $title $pickFrom { param($a) ('{0}   (rg: {1})' -f $a.StorageAccountName, $a.ResourceGroupName) } $curAcct
        $storageAccountName = $sa.StorageAccountName
        $resourceGroupName = $sa.ResourceGroupName
    }
}
catch {
    Write-Host ('Could not list storage accounts ({0}).' -f $_.Exception.Message) -ForegroundColor Yellow
}
if (-not $storageAccountName) {
    $storageAccountName = Read-Default 'Storage account name' $curAcct
    $resourceGroupName = Read-Default 'Resource group name' (Get-Prop $existing 'target.resourceGroupName' $null)
}

# --- 4) pick the container / filesystem (management plane - no data access needed) ---
$curFs = Get-Prop $existing 'target.fileSystem' $null
$fileSystem = $null
try {
    $containers = @(Get-AzRmStorageContainer -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorAction Stop)
    if ($containers.Count -gt 0) {
        $c = Select-FromList 'Containers / filesystems:' $containers { param($x) $x.Name } $curFs
        $fileSystem = $c.Name
    }
}
catch {
    Write-Host ('Could not list containers ({0}).' -f $_.Exception.Message) -ForegroundColor Yellow
}
if (-not $fileSystem) { $fileSystem = Read-Default 'Container / filesystem name' $curFs }

# --- 5) root path ---
$rootPath = Read-Default 'Root path to scan within the filesystem' (Get-Prop $existing 'target.rootPath' '/')
if (-not $rootPath) { $rootPath = '/' }

# --- 6) assemble + write (preserving non-prompted defaults) ---
$defaultScopes = @('Directory.Read.All', 'Group.Read.All', 'GroupMember.Read.All', 'User.Read.All')
$graphScopes = @(Get-Prop $existing 'auth.graphScopes' (Get-Prop $template 'auth.graphScopes' $defaultScopes))
$groups = if ($existing -and $existing.groups) { $existing.groups } elseif ($template -and $template.groups) { $template.groups } else { [pscustomobject]@{ namePrefixes = @(); expandTransitiveMembership = $true } }
$scan = if ($existing -and $existing.scan) { $existing.scan } elseif ($template -and $template.scan) { $template.scan } else { $null }
$output = if ($existing -and $existing.output) { $existing.output } elseif ($template -and $template.output) { $template.output } else { [pscustomobject]@{ format = 'both'; inventoryPath = './data/inventory.json'; inventoryJsonlPath = './data/inventory.jsonl' } }

$config = [ordered]@{
    target = [ordered]@{
        tenantId           = $tenantId
        subscriptionId     = $subscriptionId
        resourceGroupName  = $resourceGroupName
        storageAccountName = $storageAccountName
        fileSystem         = $fileSystem
        rootPath           = $rootPath
    }
    auth   = [ordered]@{
        loginHint   = $loginHint
        graphScopes = $graphScopes
    }
    groups = $groups
    scan   = $scan
    output = $output
}

$dir = Split-Path -Parent $ConfigPath
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Write-JsonFile -Path $ConfigPath -Object $config

Write-Host ''
Write-ScanLog OK ("Saved configuration to {0}" -f $ConfigPath)
Write-Host '  (local + git-ignored - not committed to the repo)' -ForegroundColor DarkGray
Write-Host ''
Write-Host ('  Tenant         : {0}' -f $tenantId)
Write-Host ('  Subscription   : {0}' -f $subscriptionId)
Write-Host ('  Resource group : {0}' -f $resourceGroupName)
Write-Host ('  Storage account: {0}' -f $storageAccountName)
Write-Host ('  Container       : {0}' -f $fileSystem)
Write-Host ('  Root path       : {0}' -f $rootPath)
Write-Host ('  Sign-in UPN     : {0}' -f $loginHint)
Write-Host ''
Write-Host 'Run  ./engine/Invoke-Scan.ps1  to start the READ-ONLY scan.' -ForegroundColor Green
