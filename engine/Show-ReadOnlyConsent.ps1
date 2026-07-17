#Requires -Version 5.1
<#
.SYNOPSIS
    Displays the READ-ONLY consent banner and asks the operator to confirm before any scan.

.DESCRIPTION
    Dot-source this script to get the Show-ReadOnlyConsent function, or run it directly to show the
    banner and get a $true/$false confirmation. It accesses nothing — it only prints and prompts.

.EXAMPLE
    . ./engine/Show-ReadOnlyConsent.ps1
    if (-not (Show-ReadOnlyConsent)) { return }
#>
[CmdletBinding()]
param(
    [switch]$AssumeYes
)

function Show-ReadOnlyConsent {
    [CmdletBinding()]
    param([switch]$AssumeYes)

    $banner = @'
============================================================
   ADLS ACL ASSESSMENT   —   READ-ONLY
============================================================
 This tool ENUMERATES (reads) ADLS Gen2 ACLs, Microsoft
 Entra ID groups, group nesting, and memberships to build
 an inventory.

 It will NOT create, modify, move, or delete anything in
 Azure or Microsoft Entra ID. No remediation is performed.
============================================================
'@

    Write-Host $banner -ForegroundColor Yellow

    if ($AssumeYes) { return $true }

    $answer = Read-Host 'Proceed with the READ-ONLY scan? [y/N]'
    $ok = $answer -match '^\s*(y|yes)\s*$'
    if (-not $ok) { Write-Host 'Cancelled. Nothing was accessed.' -ForegroundColor Red }
    return $ok
}

# Run directly (not dot-sourced) -> show the banner and return the decision.
if ($MyInvocation.InvocationName -ne '.') {
    return (Show-ReadOnlyConsent -AssumeYes:$AssumeYes)
}
