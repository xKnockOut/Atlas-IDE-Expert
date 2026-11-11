<#
.SYNOPSIS
    Hält die atlas.json aller Plugin-Packages gleich (Selbstprüfung je Package, Code-Review A-101).

.DESCRIPTION
    Atlas liest bei "AtlasServer --check <Projekt>" und im Editor die nächstgelegene
    atlas.json über dem Projekt, und daneben deren atlas-baseline.json. Damit jedes
    Plugin-Package (Packages/Atlas.IDE.*) mit demselben strengen Profil geprüft wird
    und seine eigene Baseline hat, liegt in jedem Package eine atlas.json.

    Quelle ist Packages/atlas.plugin.json (Profil, Mindestkonfidenz, Ausnahmen des
    Plugins). Die Regeln aus $SharedRules übernimmt das Skript aus der atlas.json im
    Stamm, damit Architektur- und Verbotsregeln nur an einer Stelle stehen. Die
    erzeugte Datei ist in allen Packages gleich und wird nicht von Hand geändert.

    Mit -Check schreibt das Skript nichts und meldet jede abweichende oder fehlende
    Datei (Exit-Code 1). Ohne -Check schreibt es die Dateien neu.

    Nach einer Änderung der Konfiguration die Baseline des betroffenen Packages neu
    erzeugen:
      AtlasServer --check Packages/<Package>/<Package>.dproj --update-baseline

.EXAMPLE
    pwsh Tools/Update-PackageConfigs.ps1
    pwsh Tools/Update-PackageConfigs.ps1 -Check
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Regeln, die für das ganze Repository gelten und deshalb aus der Wurzel kommen.
$SharedRules = @('architecture-role-import', 'architecture-contract-content', 'forbidden-symbol')

function Read-Json([string] $Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
}

function Get-PluginPackages([string] $RootDir) {
    return @(Get-ChildItem -LiteralPath (Join-Path $RootDir 'Packages') -Directory -Filter 'Atlas.IDE.*' |
        Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).dproj") } | Sort-Object Name)
}

function Get-PackageConfigText([string] $RootDir) {
    $mPlugin = Read-Json (Join-Path $RootDir 'Packages/atlas.plugin.json')
    $mRoot = Read-Json (Join-Path $RootDir 'atlas.json')
    foreach ($mName in $SharedRules) {
        if (-not $mRoot['rules'].Contains($mName)) {
            throw "atlas.json im Stamm hat keine Regel '$mName' (in Tools/Update-PackageConfigs.ps1 als gemeinsam geführt)."
        }
        $mPlugin['rules'][$mName] = $mRoot['rules'][$mName]
    }
    $mText = $mPlugin | ConvertTo-Json -Depth 32
    return ($mText -replace "`r`n", "`n") + "`n"
}

$Expected = Get-PackageConfigText $Root
$Problems = [System.Collections.Generic.List[string]]::new()
foreach ($mPackage in Get-PluginPackages $Root) {
    $mFile = Join-Path $mPackage.FullName 'atlas.json'
    $mRelative = "Packages/$($mPackage.Name)/atlas.json"
    $mCurrent = $null
    if (Test-Path -LiteralPath $mFile) {
        $mCurrent = (Get-Content -LiteralPath $mFile -Raw -Encoding utf8) -replace "`r`n", "`n"
    }
    if ($mCurrent -ceq $Expected) {
        continue
    }
    if ($Check) {
        if ($null -eq $mCurrent) {
            $Problems.Add("$mRelative fehlt")
        } else {
            $Problems.Add("$mRelative weicht von Packages/atlas.plugin.json und den gemeinsamen Regeln ab")
        }
    } else {
        [System.IO.File]::WriteAllText($mFile, $Expected, [System.Text.UTF8Encoding]::new($false))
        Write-Host "geschrieben: $mRelative"
    }
}

if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { Write-Host "::error::$_" }
    Write-Host 'Abhilfe: pwsh Tools/Update-PackageConfigs.ps1, danach die Baseline der geänderten Packages neu erzeugen.'
    exit 1
}
if ($Check) {
    Write-Host "Konfiguration aller Plugin-Packages aktuell."
}
exit 0
