<#
.SYNOPSIS
    Prüft Setup/tips.json, die Tippquelle der Karte „Atlas entdecken“ und der Tastenkürzel-Tipps (#757).

.DESCRIPTION
    - Format 1, mindestens ein Tipp, Kennungen eindeutig (Groß/klein egal).
    - Titel und Text je deutsch und englisch vorhanden.
    - command und Befehle unter usage, die mit "Atlas." beginnen, sind Befehle der Befehlspalette (stehen
      als 'Atlas.…' in den Quellen des Plugins).
    - setting ist ein Registry-Name aus Atlas.Core.Settings.Plugin.pas.
    - image liegt als echte PNG-Datei unter Setup/Tipps, sample unter Setup/Beispiele; line und column
      zeigen in die Datei.
    - Jedes Bild in Setup/Tipps wird von einem Tipp benutzt.

    Exit-Code 0: in Ordnung, 1: Fehler.

.EXAMPLE
    pwsh Tools/Check-Tips.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Setup = Join-Path $Root 'Setup'
$File = Join-Path $Setup 'tips.json'
$Errors = [System.Collections.Generic.List[string]]::new()

function Field($Object, [string] $Name) {
    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) { return $null }
    return $Property.Value
}

function LocalPath([string] $Relative) {
    # Wie TAtlasTipCatalog.FileIn: nur Pfade im Installationsordner.
    if ($Relative -match '\.\.|:' -or $Relative -match '^[\\/]') { return $null }
    return Join-Path $Setup ($Relative -replace '[\\/]', [IO.Path]::DirectorySeparatorChar)
}

if (-not (Test-Path $File)) {
    Write-Host "Fehler: $File fehlt"
    exit 1
}
$Json = Get-Content -Raw -Encoding utf8 $File | ConvertFrom-Json

$PluginSource = Join-Path $Root 'Packages/Atlas.IDE.Expert/Source'
$Sources = (Get-ChildItem -Recurse -Filter '*.pas' $PluginSource | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$SettingsUnit = Get-Content -Raw (Join-Path $PluginSource 'Core/Settings/Atlas.Core.Settings.Plugin.pas')
$Settings = [regex]::Matches($SettingsUnit, "ReadInteger\('([A-Za-z]+)'") | ForEach-Object { $_.Groups[1].Value }

if ((Field $Json 'format') -ne 1) { $Errors.Add('format muss 1 sein') }
$Tips = @(Field $Json 'tips')
if ($Tips.Count -eq 0) { $Errors.Add('keine Tipps') }

$Seen = @{}
$Images = @{}
foreach ($Tip in $Tips) {
    $Command = [string](Field $Tip 'command')
    $Id = [string](Field $Tip 'id')
    if ($Id -eq '') { $Id = $Command }
    if ($Id -eq '') { $Errors.Add('Tipp ohne id und command'); continue }
    $Key = $Id.ToLowerInvariant()
    if ($Seen.ContainsKey($Key)) { $Errors.Add("${Id}: Kennung doppelt") }
    $Seen[$Key] = $true
    foreach ($Name in 'title', 'titleEn', 'text', 'textEn') {
        if ([string]::IsNullOrWhiteSpace([string](Field $Tip $Name))) { $Errors.Add("${Id}: $Name fehlt") }
    }
    $Commands = @()
    if ($Command -ne '') { $Commands += $Command }
    $Usage = Field $Tip 'usage'
    if ($null -ne $Usage) { $Commands += @($Usage) }
    foreach ($Name in $Commands) {
        if ($Name -like 'Atlas.*' -and $Sources -notmatch [regex]::Escape("'$Name'")) {
            $Errors.Add("${Id}: Befehl $Name gibt es in der Befehlspalette nicht")
        }
    }
    $Setting = [string](Field $Tip 'setting')
    if ($Setting -ne '' -and $Settings -notcontains $Setting) {
        $Errors.Add("${Id}: Einstellung $Setting gibt es nicht (Registry-Name aus Atlas.Core.Settings.Plugin.pas)")
    }
    $Image = [string](Field $Tip 'image')
    if ($Image -ne '') {
        $Path = LocalPath $Image
        if ($null -eq $Path -or -not (Test-Path $Path)) {
            $Errors.Add("${Id}: Bild $Image fehlt")
        } else {
            $Bytes = [IO.File]::ReadAllBytes($Path)
            if ($Bytes.Length -lt 8 -or $Bytes[0] -ne 0x89 -or $Bytes[1] -ne 0x50 -or $Bytes[2] -ne 0x4E -or $Bytes[3] -ne 0x47) {
                $Errors.Add("${Id}: Bild $Image ist kein PNG")
            }
            $Images[(Resolve-Path $Path).Path.ToLowerInvariant()] = $true
        }
    }
    $Sample = [string](Field $Tip 'sample')
    if ($Sample -ne '') {
        $Path = LocalPath $Sample
        if ($null -eq $Path -or -not (Test-Path $Path)) {
            $Errors.Add("${Id}: Beispiel $Sample fehlt")
        } else {
            $Lines = Get-Content -Encoding utf8 $Path
            $Line = [int](Field $Tip 'line')
            $Column = [int](Field $Tip 'column')
            if ($Line -lt 0 -or $Line -gt $Lines.Count) {
                $Errors.Add("${Id}: Zeile $Line liegt nicht in $Sample")
            } elseif ($Line -gt 0 -and $Column -gt ($Lines[$Line - 1].Length + 1)) {
                $Errors.Add("${Id}: Spalte $Column liegt nicht in Zeile $Line von $Sample")
            }
        }
    }
}

foreach ($Png in Get-ChildItem (Join-Path $Setup 'Tipps') -Filter '*.png' -ErrorAction SilentlyContinue) {
    if (-not $Images.ContainsKey($Png.FullName.ToLowerInvariant())) {
        $Errors.Add("Bild Tipps/$($Png.Name) wird von keinem Tipp benutzt")
    }
}

if ($Errors.Count -gt 0) {
    $Errors | ForEach-Object { Write-Host "Fehler: $_" }
    exit 1
}
Write-Host "tips.json: $($Tips.Count) Tipps in Ordnung."
