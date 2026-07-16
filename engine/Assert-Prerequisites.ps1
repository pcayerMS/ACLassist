#Requires -Version 7.0
<#
.SYNOPSIS
    READ-ONLY prerequisite check for the ADLS ACL assessment tool.

.DESCRIPTION
    Verifies the local client has what the tool needs and OFFERS to install anything missing.
    All installs are LOCAL only (PowerShell modules for the current user, and optionally Node.js LTS).
    This script never contacts Azure or Microsoft Entra ID and never changes anything remote.

.PARAMETER AssumeYes
    Install missing/outdated prerequisites without prompting.

.PARAMETER SkipNode
    Skip the Node.js LTS check (Node is only needed for the analyzer + dashboard, not the scan).

.EXAMPLE
    pwsh ./engine/Assert-Prerequisites.ps1

.EXAMPLE
    pwsh ./engine/Assert-Prerequisites.ps1 -AssumeYes
#>
[CmdletBinding()]
param(
    [switch]$AssumeYes,
    [switch]$SkipNode
)

$ErrorActionPreference = 'Stop'

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Message)
    if ($AssumeYes) { return $true }
    $answer = Read-Host "$Message [y/N]"
    return $answer -match '^\s*(y|yes)\s*$'
}

function Get-InstalledModuleVersion {
    param([Parameter(Mandatory)][string]$Name)
    return (Get-Module -ListAvailable -Name $Name |
        Sort-Object Version -Descending |
        Select-Object -First 1).Version
}

Write-Host ''
Write-Host 'ADLS ACL assessment — prerequisite check (READ-ONLY, local only)' -ForegroundColor Cyan
Write-Host '----------------------------------------------------------------' -ForegroundColor Cyan

# --- PowerShell version -------------------------------------------------------
$psOk = $PSVersionTable.PSVersion.Major -ge 7
Write-Host ("PowerShell {0}  =>  {1}" -f $PSVersionTable.PSVersion, ($psOk ? 'OK' : 'NEEDS 7+')) `
    -ForegroundColor ($psOk ? 'Green' : 'Red')
if (-not $psOk) {
    Write-Warning 'PowerShell 7+ is required. Install from https://aka.ms/powershell and re-run this script with pwsh.'
}

# --- Required PowerShell modules ---------------------------------------------
$required = @(
    @{ Name = 'Az.Accounts';                     MinVersion = '2.12.0' }
    @{ Name = 'Az.Storage';                      MinVersion = '5.5.0'  }
    @{ Name = 'Az.Resources';                    MinVersion = '6.6.0'  }
    @{ Name = 'Microsoft.Graph.Authentication';  MinVersion = '2.0.0'  }
    @{ Name = 'Microsoft.Graph.Groups';          MinVersion = '2.0.0'  }
    @{ Name = 'Microsoft.Graph.Users';           MinVersion = '2.0.0'  }
)

$results = foreach ($mod in $required) {
    $installed = Get-InstalledModuleVersion -Name $mod.Name
    $status =
        if (-not $installed)                            { 'Missing'  }
        elseif ($installed -lt [version]$mod.MinVersion) { 'Outdated' }
        else                                             { 'OK'       }
    [pscustomobject]@{
        Component = $mod.Name
        Required  = $mod.MinVersion
        Installed = $installed
        Status    = $status
    }
}

Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host

$toInstall = $results | Where-Object { $_.Status -in @('Missing', 'Outdated') }
if ($toInstall) {
    Write-Host ("{0} module(s) need installing/upgrading." -f $toInstall.Count) -ForegroundColor Yellow
    if (Confirm-Action "Install/upgrade them for the CURRENT USER from the PowerShell Gallery?") {
        foreach ($item in $toInstall) {
            Write-Host ("Installing {0} ..." -f $item.Component) -ForegroundColor Cyan
            Install-Module -Name $item.Component -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
        }
        Write-Host 'Module installation complete.' -ForegroundColor Green
    }
    else {
        Write-Warning 'Skipped. The engine cannot run until these modules are installed.'
    }
}
else {
    Write-Host 'All required PowerShell modules are present.' -ForegroundColor Green
}

# --- Node.js LTS (for analyzer + dashboard) ----------------------------------
if (-not $SkipNode) {
    Write-Host ''
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $nodeVersion = (& node --version).Trim()
        Write-Host ("Node.js {0}  =>  OK" -f $nodeVersion) -ForegroundColor Green
    }
    else {
        Write-Host 'Node.js LTS not found (needed for the analyzer + dashboard, not for the scan).' -ForegroundColor Yellow
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($IsWindows -and $winget) {
            if (Confirm-Action 'Install Node.js LTS via winget (OpenJS.NodeJS.LTS)?') {
                winget install --id OpenJS.NodeJS.LTS -e --source winget
            }
            else {
                Write-Warning 'Skipped Node.js install. Get the LTS from https://nodejs.org/en when you reach M2/M3.'
            }
        }
        else {
            Write-Warning 'Install Node.js LTS from https://nodejs.org/en (needed at M2/M3).'
        }
    }
}

# --- Summary (recompute module state so it reflects any installs above) -------
Write-Host ''
$missingNow = foreach ($mod in $required) {
    $v = Get-InstalledModuleVersion -Name $mod.Name
    if (-not $v -or $v -lt [version]$mod.MinVersion) { $mod.Name }
}
if (-not $psOk -or $missingNow) {
    Write-Host 'Prerequisite check finished with items still outstanding — see the warnings above.' -ForegroundColor Yellow
    if ($missingNow) { Write-Host ("  Still needed: {0}" -f ($missingNow -join ', ')) -ForegroundColor Yellow }
}
else {
    Write-Host 'Prerequisites satisfied. Configure config/config.json and run the scan (M1).' -ForegroundColor Green
}

return $results
