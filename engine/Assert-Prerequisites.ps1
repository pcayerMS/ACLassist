#Requires -Version 5.1
<#
.SYNOPSIS
    READ-ONLY prerequisite check for the ADLS ACL assessment engine.

.DESCRIPTION
    Runs on built-in Windows PowerShell 5.1 or on PowerShell 7. Verifies the Az + Microsoft.Graph
    modules the read-only scan needs, and OFFERS to install any that are missing (Install-Module, current
    user). Installs are LOCAL PowerShell modules only - this never contacts Azure/Entra and changes
    nothing remote. The dashboard needs no install at all: open dashboard/ACLassist.html in any browser.

.PARAMETER AssumeYes
    Install missing/outdated modules without prompting.

.EXAMPLE
    powershell -File ./engine/Assert-Prerequisites.ps1     # Windows PowerShell 5.1 (built-in)

.EXAMPLE
    pwsh ./engine/Assert-Prerequisites.ps1 -AssumeYes      # PowerShell 7
#>
[CmdletBinding()]
param(
    [switch]$AssumeYes
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
Write-Host 'ADLS ACL assessment - prerequisite check (READ-ONLY, local only)' -ForegroundColor Cyan
Write-Host '----------------------------------------------------------------' -ForegroundColor Cyan

# --- PowerShell version (Windows PowerShell 5.1 built-in is fine; 7 also works) ---
$psVersion = $PSVersionTable.PSVersion
$psOk = $psVersion -ge [version]'5.1'
$psLabel = 'OK (5.1+)'
$psColor = 'Green'
if (-not $psOk) { $psLabel = 'NEEDS 5.1+'; $psColor = 'Red' }
Write-Host ("PowerShell {0}  =>  {1}" -f $psVersion, $psLabel) -ForegroundColor $psColor

# --- Required PowerShell modules (support Windows PowerShell 5.1 and PowerShell 7) ---
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
    $status = 'OK'
    if (-not $installed) { $status = 'Missing' }
    elseif ($installed -lt [version]$mod.MinVersion) { $status = 'Outdated' }
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
    if (Confirm-Action 'Install/upgrade them for the CURRENT USER from the PowerShell Gallery?') {
        # Windows PowerShell 5.1 may need the NuGet provider + a trusted PSGallery before Install-Module.
        if ($psVersion.Major -lt 6) {
            try { if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null } } catch { }
        }
        try { if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } } catch { }
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

# --- Summary (recompute module state so it reflects any installs above) -------
Write-Host ''
$missingNow = foreach ($mod in $required) {
    $ver = Get-InstalledModuleVersion -Name $mod.Name
    if (-not $ver -or $ver -lt [version]$mod.MinVersion) { $mod.Name }
}
if (-not $psOk -or $missingNow) {
    Write-Host 'Prerequisite check finished with items still outstanding - see the warnings above.' -ForegroundColor Yellow
    if ($missingNow) { Write-Host ("  Still needed: {0}" -f ($missingNow -join ', ')) -ForegroundColor Yellow }
}
else {
    Write-Host 'Prerequisites satisfied. Configure config/config.json and run the scan.' -ForegroundColor Green
}
Write-Host 'Dashboard: no install needed - just open dashboard/ACLassist.html in any browser.' -ForegroundColor Gray

return $results
