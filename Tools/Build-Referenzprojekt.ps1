<#
.SYNOPSIS
    Baut das Referenz-Testprojekt über Tools/Build-Ide.ps1 für Win32 und Win64 und prüft die gewollten Meldungen
    (#94, #1904).

.DESCRIPTION
    Für Tests/Referenzprojekt:

    1. Tools/Build-Ide.ps1 -Project RefGruppe.groupproj -Platform <p> -Mode build
       -Json je Plattform (Vorgabe Win32 und Win64) in einer eigenen Bau-IDE
       (Registry-Profil AtlasBuild, feste Plugin-Kopie über -Setup); eine schon
       laufende IDE bleibt unberührt. ok muss gesetzt sein.
    2. Hinweise und Warnungen aus steps[].messages werden mit
       erwartete-meldungen.txt verglichen: Jede Zeile der Liste muss je Plattform
       genau einmal kommen, jede andere Meldung lässt den Build scheitern.
    3. Mit -MitDaten zusätzlich das optionale Projekt RefDaten (FireDAC); dort
       gelten dieselbe Liste und dieselben Regeln.
    4. Die .dproj- und .groupproj-Dateien dürfen sich dabei nicht ändern; sonst
       hat die IDE sie umgeschrieben, und sie müssen einmal in der IDE gespeichert
       und eingecheckt werden.

    Exit-Code 0: alles wie erwartet. 1: Build-Fehler, fehlende oder unerwartete
    Meldung oder geänderte Projektdatei. 3: Aufruf- oder Umgebungsfehler.

.EXAMPLE
    pwsh Tools/Build-Referenzprojekt.ps1
    pwsh Tools/Build-Referenzprojekt.ps1 -MitDaten
    pwsh Tools/Build-Referenzprojekt.ps1 -Platforms Win32
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    # Bau-Skript mit den Parametern von Tools/Build-Ide.ps1; Vorgabe Tools/Build-Ide.ps1.
    [string] $BuildScript = (Join-Path $PSScriptRoot 'Build-Ide.ps1'),
    [string[]] $Platforms = @('Win32', 'Win64'),
    [switch] $MitDaten
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectDir = Join-Path $Root 'Tests/Referenzprojekt'
$GroupProject = Join-Path $ProjectDir 'RefGruppe.groupproj'
$DataProject = Join-Path $ProjectDir 'RefDaten.dproj'
$ExpectedFile = Join-Path $ProjectDir 'erwartete-meldungen.txt'
function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

# Baut ein Projekt oder eine Gruppe über das Bau-Skript; liefert dessen JSON-Antwort.
function Invoke-DelphiBuild([string] $Project, [string] $Platform) {
    $output = & { Set-StrictMode -Off; & $BuildScript -Project $Project -Platform $Platform -Mode build -Json } |
        Out-String
    $start = $output.IndexOf('{')
    if ($start -lt 0) { throw "Das Bau-Skript lieferte kein JSON:`n$output" }
    $output.Substring($start) | ConvertFrom-Json
}

function Get-Property($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null }
}

# Liest erwartete-meldungen.txt: je Zeile Datei, Code und Bezeichner, durch Leerraum getrennt; # leitet Kommentare ein.
function Read-ExpectedMessages([string] $Path) {
    $result = @()
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        $text = ($line -replace '#.*$', '').Trim()
        if ($text -eq '') { continue }
        $parts = $text -split '\s+'
        if ($parts.Count -ne 3) { throw "Ungültige Zeile in $(Split-Path -Leaf $Path): $line" }
        $result += [pscustomobject]@{ File = $parts[0]; Code = $parts[1]; Name = $parts[2] }
    }
    $result
}

# Vergleicht die Meldungen eines Baus mit der Liste; liefert die Verstöße (leer = in Ordnung).
function Test-Messages($Messages, $Expected, [string] $Label) {
    $problems = @()
    $counts = @{}
    foreach ($message in @($Messages)) {
        if ($null -eq $message) { continue }
        $file = $(if ($message.file) { Split-Path -Leaf ([string] $message.file) } else { '' })
        $line = "[$($message.severity)] $file($($message.line)): $($message.code) $($message.text)"
        if ($message.severity -notmatch '^(hint|warning)') {
            $problems += "$Label`: $line"
            continue
        }
        $match = $Expected | Where-Object {
            $_.File -eq $file -and $_.Code -eq $message.code -and
                [string] $message.text -match ("'" + [regex]::Escape($_.Name) + "'")
        } | Select-Object -First 1
        if ($null -eq $match) {
            $problems += "$Label`: unerwartet: $line"
        } else {
            $key = "$($match.File)|$($match.Code)|$($match.Name)"
            $counts[$key] = 1 + $(if ($counts.ContainsKey($key)) { $counts[$key] } else { 0 })
        }
    }
    foreach ($item in $Expected) {
        $key = "$($item.File)|$($item.Code)|$($item.Name)"
        $count = $(if ($counts.ContainsKey($key)) { $counts[$key] } else { 0 })
        if ($count -eq 0) { $problems += "$Label`: fehlt: $($item.Code) $($item.Name) in $($item.File)" }
        elseif ($count -gt 1) { $problems += "$Label`: $count-mal statt einmal: $($item.Code) $($item.Name) in $($item.File)" }
    }
    $problems
}

function Test-Build($Result, $Expected, [string] $Label) {
    $problems = @()
    if (-not (Get-Property $Result 'ok')) { $problems += "$Label`: Bau meldet ok = false" }
    $messages = @()
    foreach ($step in @(Get-Property $Result 'steps')) {
        if ($null -eq $step) { continue }
        $reason = Get-Property $step 'reason'
        if ($reason) { $problems += "$Label`: $(Get-Property $step 'project'): $reason" }
        $messages += @(Get-Property $step 'messages')
    }
    $problems += Test-Messages $messages $Expected $Label
    $problems
}

function Get-ProjectFileHashes {
    $hashes = @{}
    Get-ChildItem -Path $ProjectDir -File | Where-Object { $_.Extension -in '.dproj', '.groupproj' } | ForEach-Object {
        $hashes[$_.Name] = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    }
    $hashes
}

foreach ($path in @($BuildScript, $GroupProject, $ExpectedFile)) {
    if (-not (Test-Path $path)) {
        Write-Error "Nicht gefunden: $path" -ErrorAction Continue
        exit 3
    }
}

$exitCode = 0
$problems = @()
$hashesBefore = Get-ProjectFileHashes
try {
    $expected = @(Read-ExpectedMessages $ExpectedFile)

    foreach ($platform in $Platforms) {
        Write-Step "RefGruppe bauen ($platform)"
        $problems += Test-Build (Invoke-DelphiBuild $GroupProject $platform) $expected "RefGruppe $platform"
        if ($MitDaten) {
            Write-Step "RefDaten bauen ($platform)"
            $problems += Test-Build (Invoke-DelphiBuild $DataProject $platform) $expected "RefDaten $platform"
        }
    }
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 3
}

if ($exitCode -eq 0) {
    $hashesAfter = Get-ProjectFileHashes
    foreach ($name in $hashesBefore.Keys) {
        if ($hashesAfter[$name] -ne $hashesBefore[$name]) {
            $problems += "$name wurde von der IDE geändert: einmal in der IDE speichern und so einchecken"
        }
    }
    if ($problems.Count -gt 0) {
        Write-Step 'Referenzprojekt weicht ab'
        $problems | ForEach-Object { Write-Host "  $_" }
        $exitCode = 1
    } else {
        Write-Step 'Referenzprojekt wie erwartet übersetzt'
    }
}
exit $exitCode
