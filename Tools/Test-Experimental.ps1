<#
.SYNOPSIS
    Prüft die Wächter in Update-ConfigDoc.ps1: experimentelle Funktionen (#834)
    und veraltete erzeugte Dateien unabhängig von den Zeilenenden (#888).

.DESCRIPTION
    Legt eine Kopie von Schemas, Doku, Paketen und Profilen in einem temporären
    Ordner an, baut darin je Fall einen Fehler ein und erwartet, dass
    Update-ConfigDoc.ps1 -Check scheitert und den Fehler nennt. Der
    unveränderte Stand muss die Prüfung bestehen, auch wenn der Checkout andere
    Zeilenenden hat (Linux-Runner: LF, Windows: CRLF).

.EXAMPLE
    pwsh Tools/Test-Experimental.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script = Join-Path $PSScriptRoot 'Update-ConfigDoc.ps1'
$Failures = [System.Collections.Generic.List[string]]::new()

function New-Copy {
    $Target = Join-Path ([IO.Path]::GetTempPath()) ('atlas-experimental-' + [Guid]::NewGuid().ToString('N'))
    foreach ($Folder in 'schemas', 'docs', 'Packages', 'Setup/Profile') {
        $Destination = Join-Path $Target $Folder
        New-Item -ItemType Directory -Force (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -Recurse (Join-Path $Root $Folder) $Destination
    }
    return $Target
}

function Invoke-Check([string] $CopyRoot) {
    $Output = & pwsh -NoProfile -File $Script -Root $CopyRoot -Check 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $Output }
}

function Edit-Json([string] $Path, [scriptblock] $Change) {
    $Data = Get-Content -Raw -Encoding utf8 $Path | ConvertFrom-Json -AsHashtable
    & $Change $Data
    [IO.File]::WriteAllText($Path, ($Data | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
}

function Test-Case([string] $Name, [string] $Expected, [scriptblock] $Break) {
    $CopyRoot = New-Copy
    try {
        & $Break $CopyRoot
        $Result = Invoke-Check $CopyRoot
        if ($Result.Code -eq 0) { $Failures.Add("${Name}: Prüfung bestand trotz Fehler") }
        elseif ($Result.Output -notlike "*$Expected*") { $Failures.Add("${Name}: erwartet [$Expected], erhalten:`n$($Result.Output)") }
        else { Write-Host "ok: $Name" }
    }
    finally {
        Remove-Item -Recurse -Force $CopyRoot
    }
}

function Test-Pass([string] $Name, [scriptblock] $Change) {
    $CopyRoot = New-Copy
    try {
        & $Change $CopyRoot
        $Result = Invoke-Check $CopyRoot
        if ($Result.Code -ne 0) { $Failures.Add("${Name}: Prüfung scheitert:`n$($Result.Output)") }
        else { Write-Host "ok: $Name" }
    }
    finally {
        Remove-Item -Recurse -Force $CopyRoot
    }
}

# Schreibt alle Textdateien der Kopie mit dem angegebenen Zeilenende neu.
function Set-LineEndings([string] $CopyRoot, [string] $Ending) {
    Get-ChildItem -Recurse -File $CopyRoot -Include '*.md', '*.json', '*.pas' | ForEach-Object {
        $Bytes = [IO.File]::ReadAllBytes($_.FullName)
        $Text = [Text.Encoding]::UTF8.GetString($Bytes)
        $Normal = $Text.Replace("`r`n", "`n")
        if ($Ending -ne "`n") { $Normal = $Normal.Replace("`n", $Ending) }
        [IO.File]::WriteAllBytes($_.FullName, [Text.Encoding]::UTF8.GetBytes($Normal))
    }
}

# Ausgangsstand besteht, mit LF wie auf dem Linux-Runner und mit CRLF wie unter Windows.
Test-Pass 'Ausgangsstand' { param($CopyRoot) }
Test-Pass 'Zeilenenden LF' { param($CopyRoot) Set-LineEndings $CopyRoot "`n" }
Test-Pass 'Zeilenenden CRLF' { param($CopyRoot) Set-LineEndings $CopyRoot "`r`n" }

Test-Case 'Konfiguration.md veraltet' 'Konfiguration.md ist veraltet' {
    param($CopyRoot)
    $Path = Join-Path $CopyRoot 'docs/Konfiguration.md'
    [IO.File]::AppendAllText($Path, "`nveraltete Zeile`n", [Text.UTF8Encoding]::new($false))
}

Test-Case 'Vorgabe an' 'statt aus' {
    param($CopyRoot)
    Edit-Json (Join-Path $CopyRoot 'schemas/atlas-plugin.schema.json') {
        param($Data)
        $Entry = $Data['properties'].Values | Where-Object { $_['type'] -eq 'boolean' -and $_['default'] -eq $true } | Select-Object -First 1
        $Entry['x-experimental'] = $true
    }
}

Test-Case 'Objekt experimentell' 'gehört an die einzelnen Einstellungen' {
    param($CopyRoot)
    $Path = Join-Path $CopyRoot 'schemas/atlas.schema.json'
    $Text = [IO.File]::ReadAllText($Path)
    $Text = $Text -replace '("experimental"\s*:\s*\{)', '$1 "x-experimental": true,'
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

Test-Case 'Hauptschalter experimentell' 'Hauptschalter' {
    param($CopyRoot)
    Edit-Json (Join-Path $CopyRoot 'schemas/atlas-plugin.schema.json') {
        param($Data)
        $Data['properties']['ExperimentalEnabled']['x-experimental'] = $true
    }
}

Test-Case 'Profil alles-an mit Hauptschalter' 'gehört nur in alles-an-experimentell.json' {
    param($CopyRoot)
    Edit-Json (Join-Path $CopyRoot 'Setup/Profile/alles-an.json') {
        param($Data)
        $Data['settings']['experimental.enabled'] = $true
    }
}

Test-Case 'Profil alles-an-experimentell fehlt' 'alles-an-experimentell.json fehlt' {
    param($CopyRoot)
    Remove-Item (Join-Path $CopyRoot 'Setup/Profile/alles-an-experimentell.json')
}

if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Host 'Wächter für experimentelle Funktionen und veraltete Doku: alle Fälle erkannt.'
# Der letzte Fall endet absichtlich mit Exit-Code 1 des Kindprozesses; ohne
# ausdrückliches exit 0 übernimmt die pwsh-Shell von GitHub Actions $LASTEXITCODE (#888).
exit 0
