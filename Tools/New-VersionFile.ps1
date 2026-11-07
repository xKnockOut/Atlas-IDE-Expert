<#
.SYNOPSIS
    Schreibt die Versionsdatei atlas-version.json für Update-Prüfung und
    Update-Installer (#495, #1519).

.DESCRIPTION
    Inhalt: Version, Link zu den Änderungen, je CompilerVersion der IDE ein
    Release-Paket (37.0 = Delphi 13) und der Quelltext, je mit SHA-256. Ohne
    Paket fehlt "packages"; dann meldet das Plugin die Version, der
    Update-Installer bricht aber mit „kein Paket“ ab.

    Aufrufer: der Release-Workflow (ohne oder mit Paket vom Delphi-Runner) und
    Publish-ReleasePackage.ps1 (Paket lokal gebaut und nachträglich angehängt).
    Beide schreiben so dieselbe Datei.

.EXAMPLE
    pwsh Tools/New-VersionFile.ps1 -Version 2.0.0 -Repository xKnockOut/Atlas-IDE-Expert `
        -SourceZip atlas-ide-expert-source-2.0.0.zip -PackageZip atlas-ide-expert-2.0.0.zip -OutFile atlas-version.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [string] $SourceZip,
    [string] $PackageZip = '',
    [string] $Ide = '37.0',
    [string] $ServerUrl = 'https://github.com',
    [Parameter(Mandatory)] [string] $OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Datei fehlt: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$Tag = "v$Version"
$Base = "$ServerUrl/$Repository/releases/download/$Tag"
$Manifest = [ordered]@{
    version = $Version
    changes = "$ServerUrl/$Repository/releases/tag/$Tag"
}
if ($PackageZip) {
    $Manifest.packages = [ordered]@{
        $Ide = [ordered]@{
            url    = "$Base/$(Split-Path -Leaf $PackageZip)"
            sha256 = Get-Sha256 $PackageZip
        }
    }
}
$Manifest.source = [ordered]@{
    url    = "$Base/$(Split-Path -Leaf $SourceZip)"
    sha256 = Get-Sha256 $SourceZip
}
$Json = $Manifest | ConvertTo-Json -Depth 5 -Compress
[IO.File]::WriteAllText($OutFile, $Json + "`n", [Text.UTF8Encoding]::new($false))
$Json
