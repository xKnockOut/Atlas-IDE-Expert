<#
.SYNOPSIS
    Gibt die Release-Notizen einer Version aus (#83).

.DESCRIPTION
    Gibt es docs/Release-Notizen/<Version>.md, sind das die Notizen: eine kurze Fassung
    für Versionen, deren Changelog-Abschnitt zu lang für ein GitHub Release ist. Sonst
    kommt der Abschnitt aus CHANGELOG.md (Get-ChangelogSection.ps1).

    GitHub nimmt höchstens 125000 Zeichen als Text eines Release an; längere Notizen
    lehnt die API ab, und der Release-Workflow scheitert erst nach dem Bauen. Das Skript
    bricht deshalb schon vorher mit Exit-Code 1 ab, ebenso bei leeren Notizen.

.EXAMPLE
    pwsh Tools/Get-ReleaseNotes.ps1 -Version 1.1.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GitHubLimit = 125000
$Summary = Join-Path $Root "docs/Release-Notizen/$Version.md"
if (Test-Path $Summary) {
    $Notes = ([IO.File]::ReadAllText($Summary)).Trim()
} else {
    $Notes = & (Join-Path $PSScriptRoot 'Get-ChangelogSection.ps1') -Version $Version -Root $Root
}
if ([string]::IsNullOrWhiteSpace($Notes)) {
    Write-Error "Keine Release-Notizen für ${Version}: weder docs/Release-Notizen/$Version.md noch ein Abschnitt [$Version] in CHANGELOG.md"
}
if ($Notes.Length -gt $GitHubLimit) {
    Write-Error ("Release-Notizen für $Version haben $($Notes.Length) Zeichen, GitHub nimmt höchstens $GitHubLimit; " +
        "eine kurze Fassung in docs/Release-Notizen/$Version.md anlegen")
}
$Notes
