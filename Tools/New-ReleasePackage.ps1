<#
.SYNOPSIS
    Packt das Release-Paket atlas-ide-expert-<Version>.zip aus den
    Release-Builds unter Output (#495, #1519).

.DESCRIPTION
    Erwartet die Release-Builds wie im Release-Workflow:
    - Output\Win64\Release\Bin: AtlasServer.exe, AtlasServer.map, AtlasUpdate.exe
    - Output\Win32\Release\Bpl und Output\Win64\Release\Bpl: Kern und jedes
      Modul-Package (Packages\Atlas.IDE.*), je mit Map-Datei.

    Aufbau wie der Zielordner: Server, Updater und Daten oben, die
    BPLs je Plattform darunter. Der Release-Workflow ruft das Skript auf dem
    Delphi-Runner auf; ohne Runner baut man lokal und hängt das Paket mit
    Publish-ReleasePackage.ps1 an das Release.

    Bricht ab, wenn eine Datei fehlt, eine BPL keine Map hat, die Version im
    Quelltext nicht passt oder (im Git-Checkout) eine EXE oder BPL älter als der
    letzte Commit ist, also nicht aus diesem Stand gebaut wurde.

.EXAMPLE
    pwsh Tools/New-ReleasePackage.ps1 -Version 2.0.0-beta.1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $OutFile = '',
    # Ordner der Builds; Vorgabe <Root>\Output.
    [string] $Output = '',
    # Nur für Test-ReleasePackage.ps1: ohne HTML-Doku (Build-Docs braucht Markdig).
    [switch] $NoDocs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Join([string[]] $Parts) {
    $Path = $Parts[0]
    foreach ($Part in $Parts[1..($Parts.Count - 1)]) {
        $Path = Join-Path $Path $Part
    }
    $Path
}

function Assert-File([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Datei fehlt: $Path (Release-Build fehlt?)"
    }
}

if (-not $Output) {
    $Output = Join-Path $Root 'Output'
}
$Bin = Join $Output, 'Win64', 'Release', 'Bin'
if (-not $OutFile) {
    $OutFile = Join-Path $Bin "atlas-ide-expert-$Version.zip"
}

# Check-Version und Check-Tips enden bei einem Fehler mit exit 1; das bricht nur das gerufene Skript ab.
$global:LASTEXITCODE = 0
& (Join-Path $PSScriptRoot 'Check-Version.ps1') -Expected $Version -Root $Root | Out-Null
if ($global:LASTEXITCODE -ne 0) {
    throw "Version im Quelltext ist nicht $Version (Check-Version.ps1)"
}

# Kern und jedes Modul-Package (#1456): Ordner Packages\Atlas.IDE.* mit gleichnamigem .dpk.
$Packages = @(Get-ChildItem (Join-Path $Root 'Packages') -Directory -Filter 'Atlas.IDE.*' |
    Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).dpk") } | ForEach-Object Name | Sort-Object)
if ($Packages.Count -eq 0) {
    throw 'Keine Plugin-Packages unter Packages\Atlas.IDE.* gefunden'
}

$Built = [System.Collections.Generic.List[IO.FileInfo]]::new()
foreach ($Name in 'AtlasServer.exe', 'AtlasServer.map', 'AtlasUpdate.exe') {
    Assert-File (Join-Path $Bin $Name)
}
$Built.Add((Get-Item -LiteralPath (Join-Path $Bin 'AtlasServer.exe')))
$Built.Add((Get-Item -LiteralPath (Join-Path $Bin 'AtlasUpdate.exe')))

$Bpls = @{}
foreach ($Platform in 'Win32', 'Win64') {
    $BplDir = Join $Output, $Platform, 'Release', 'Bpl'
    $Bpls[$Platform] = [System.Collections.Generic.List[IO.FileInfo]]::new()
    foreach ($Name in $Packages) {
        # Mit LIBSUFFIX AUTO heißen BPL und Map z. B. Atlas.IDE.Base370.bpl und Atlas.IDE.Base370.map.
        $Bpl = Get-ChildItem $BplDir -Filter "$Name*.bpl" -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match ('^' + [regex]::Escape($Name) + '\d*$') } | Select-Object -First 1
        if (-not $Bpl) {
            throw "$Platform-BPL von $Name fehlt in $BplDir"
        }
        Assert-File ([IO.Path]::ChangeExtension($Bpl.FullName, '.map'))
        $Bpls[$Platform].Add($Bpl)
        $Built.Add($Bpl)
    }
}

# Im Git-Checkout: Jede EXE und BPL muss nach dem letzten Commit gebaut sein.
$CommitTime = $null
if (Test-Path (Join-Path $Root '.git')) {
    $Iso = git -C $Root log -1 --format=%cI 2>$null
    if ($LASTEXITCODE -eq 0 -and $Iso) {
        $CommitTime = [DateTimeOffset]::Parse($Iso).UtcDateTime
    }
}
if ($CommitTime) {
    $Stale = @($Built | Where-Object { $_.LastWriteTimeUtc -lt $CommitTime })
    if ($Stale.Count -gt 0) {
        throw ("Älter als der letzte Commit ($($CommitTime.ToString('u'))), also nicht aus diesem Stand gebaut: " +
            (($Stale | ForEach-Object Name) -join ', '))
    }
}

$Dist = Join-Path ([IO.Path]::GetTempPath()) ('atlas-ide-expert-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force (Join-Path $Dist 'Win32'), (Join-Path $Dist 'Win64') | Out-Null
    # AtlasUpdate.exe (#1519): Erstinstallation („install“) und Updates aus dem Plugin.
    Copy-Item (Join-Path $Bin 'AtlasServer.exe'), (Join-Path $Bin 'AtlasUpdate.exe'), (Join-Path $Bin 'AtlasServer.map') $Dist
    Copy-Item (Join-Path $Root 'LICENSE'), (Join-Path $Root 'EULA.txt'), (Join-Path $Root 'THIRD-PARTY-NOTICES.md') $Dist
    # Karte „Neu in Atlas“ (#756): whatsnew.json aus den markierten Einträgen des Changelogs, dazu die Beispiele.
    & (Join-Path $PSScriptRoot 'Update-WhatsNew.ps1') -Root $Root -OutFile (Join-Path $Dist 'whatsnew.json') | Out-Null
    Copy-Item (Join $Root, 'Setup', 'Beispiele') (Join-Path $Dist 'Beispiele') -Recurse
    # Karte „Atlas entdecken“ und Tastenkürzel-Tipps (#757): Tippquelle und Bilder; vorher prüfen.
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot 'Check-Tips.ps1') -Root $Root | Out-Null
    if ($global:LASTEXITCODE -ne 0) {
        throw 'Tipps unvollständig (Check-Tips.ps1)'
    }
    Copy-Item (Join $Root, 'Setup', 'tips.json') $Dist
    Copy-Item (Join $Root, 'Setup', 'Tipps') (Join-Path $Dist 'Tipps') -Recurse
    # „Atlas-Doku“ der Willkommensseite (#766): Nutzer-Doku als HTML im Ordner Doku.
    if (-not $NoDocs) {
        & (Join-Path $PSScriptRoot 'Build-Docs.ps1') -Root $Root -OutDir (Join-Path $Dist 'Doku') | Out-Null
    }
    # „Projekt für Atlas einrichten“ (#759) und eingebaute Einstellungsprofile (#723).
    Copy-Item (Join $Root, 'Setup', 'Vorlagen') (Join-Path $Dist 'Vorlagen') -Recurse
    Copy-Item (Join $Root, 'Setup', 'Profile') (Join-Path $Dist 'Profile') -Recurse
    # Kern und Modul-Packages (#1456) liegen gemeinsam im Ordner der Plattform, jede mit ihrer Map unter dem Namen der BPL.
    foreach ($Platform in 'Win32', 'Win64') {
        $BplDir = Join $Output, $Platform, 'Release', 'Bpl'
        foreach ($Bpl in $Bpls[$Platform]) {
            $Target = Join-Path (Join-Path $Dist $Platform) $Bpl.Name
            Copy-Item -LiteralPath $Bpl.FullName $Target
            $Map = [IO.Path]::ChangeExtension($Bpl.FullName, '.map')
            Copy-Item -LiteralPath $Map ([IO.Path]::ChangeExtension($Target, '.map'))
        }
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent ([IO.Path]::GetFullPath($OutFile))) | Out-Null
    Compress-Archive -Path (Join-Path $Dist '*') -DestinationPath $OutFile -Force
} finally {
    Remove-Item $Dist -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Release-Paket: $OutFile ($($Packages.Count) Packages je Plattform)"
