<#
.SYNOPSIS
    Gibt den Abschnitt einer Version aus CHANGELOG.md aus (für die Release-Notizen, #83).

.EXAMPLE
    pwsh Tools/Get-ChangelogSection.ps1 -Version 0.2.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Lines = Get-Content (Join-Path $Root 'CHANGELOG.md')
$Inside = $false
$Result = foreach ($Line in $Lines) {
    if ($Line -match '^## \[') {
        if ($Inside) { break }
        $Inside = $Line -match "^## \[$([regex]::Escape($Version))\]"
        continue
    }
    # Markierungen für whatsnew.json (#756, Update-WhatsNew.ps1) gehören nicht in die Release-Notizen.
    if ($Inside) { $Line -replace '\s*<!--\s*whatsnew\b.*?-->', '' }
}
($Result -join "`n").Trim()
