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

    Mit -UnsignedBinaries kommt am Ende ein sichtbarer Hinweis auf Deutsch und
    Englisch dazu, dass EXE, BPL und DLL ohne Code-Signing-Zertifikat gebaut
    sind und Updates über die signierte Versionsdatei geprüft werden. Der
    Release-Workflow und Publish-ReleasePackage.ps1 setzen ihn, wenn die
    Binärdateien nicht signiert sind.

.EXAMPLE
    pwsh Tools/Get-ReleaseNotes.ps1 -Version 1.1.0

.EXAMPLE
    pwsh Tools/Get-ReleaseNotes.ps1 -Version 2.3.0 -UnsignedBinaries
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $UnsignedBinaries
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
if ($UnsignedBinaries) {
    $Notes += "`n`n" + ('> **Hinweis:** Die Binärdateien dieses Releases (EXE, BPL, DLL) sind nicht signiert. ' +
        'Updates prüft AtlasUpdate über die signierte Versionsdatei.') + "`n>`n" +
        ('> **Note:** The binaries of this release (EXE, BPL, DLL) are not signed. ' +
        'AtlasUpdate verifies updates through the signed version file.')
}
if ($Notes.Length -gt $GitHubLimit) {
    Write-Error ("Release-Notizen für $Version haben $($Notes.Length) Zeichen, GitHub nimmt höchstens $GitHubLimit; " +
        "eine kurze Fassung in docs/Release-Notizen/$Version.md anlegen")
}
$Notes
