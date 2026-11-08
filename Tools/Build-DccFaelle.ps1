<#
.SYNOPSIS
    Übersetzt die dcc-Minimalfälle aus Tests/DccFaelle über Tools/Build-Ide.ps1 und schreibt alle dcc-Meldungen
    in eine Datei (#1328, #1904).

.DESCRIPTION
    Die Fälle zeigen, welche Muster Delphi annimmt und welche es meldet. Danach
    richten sich die Compilerregeln („wie Exxxx“), damit Atlas nicht strenger
    meldet als dcc. Jedes Projekt wird einzeln gebaut, damit ein Fehler in einem
    Fall die anderen nicht verdeckt. Projekte ohne „Gegen“ sollen sauber
    übersetzen, Projekte mit „Gegen“ enthalten Fälle, die dcc vermutlich meldet.

    1. Tools/Build-Ide.ps1 -Project <dproj> -Platform <p> -Mode build -Json je
       Projekt und Plattform (Vorgabe Win32 und Win64); die Bau-IDE läuft im
       eigenen Registry-Profil, eine schon laufende IDE bleibt unberührt.
    2. Jede Meldung aus steps[].messages übernehmen, dazu die Fallmarke
       (// PA1 …) aus der gemeldeten Quellzeile.

    Das Ergebnis steht in Output/DccFaelle-Ergebnis.txt.

    Exit-Code 0: alle Projekte gebaut (mit oder ohne Meldungen). 3: Aufruf- oder
    Umgebungsfehler.

.EXAMPLE
    pwsh Tools/Build-DccFaelle.ps1
    pwsh Tools/Build-DccFaelle.ps1 -Platforms Win32
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    # Bau-Skript mit den Parametern von Tools/Build-Ide.ps1; Vorgabe Tools/Build-Ide.ps1.
    [string] $BuildScript = (Join-Path $PSScriptRoot 'Build-Ide.ps1'),
    [string[]] $Platforms = @('Win32', 'Win64')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CaseDir = Join-Path $Root 'Tests/DccFaelle'
$GroupProject = Join-Path $CaseDir 'DccFaelle.groupproj'
$ResultFile = Join-Path $Root 'Output/DccFaelle-Ergebnis.txt'

function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

# Baut ein Projekt über das Bau-Skript; liefert dessen JSON-Antwort und die rohe Ausgabe.
function Invoke-DelphiBuild([string] $Project, [string] $Platform) {
    $output = & { Set-StrictMode -Off; & $BuildScript -Project $Project -Platform $Platform -Mode build -Json } *>&1 |
        Out-String
    $result = $null
    $start = $output.IndexOf('{')
    if ($start -ge 0) {
        try { $result = $output.Substring($start) | ConvertFrom-Json } catch { $result = $null }
    }
    [pscustomobject]@{ Output = $output; Result = $result }
}

function Get-Property($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null }
}

# Liefert die Fallmarke (PA1, IV2 …) aus der Quellzeile einer Meldung, sonst ''.
function Get-CaseMark([string] $File, [int] $Number) {
    if (-not $File) { return '' }
    $path = Join-Path $CaseDir (Split-Path -Leaf $File)
    if (-not (Test-Path $path)) { return '' }
    $lines = @(Get-Content -Path $path -Encoding UTF8)
    if ($Number -lt 1 -or $Number -gt $lines.Count) { return '' }
    if ($lines[$Number - 1] -match '//\s*([A-Z]{2}\d+)') { return $Matches[1] }
    ''
}

function Get-BuildReport([string] $Project, [string] $Platform, $Build) {
    $report = @()
    $result = $Build.Result
    $ok = Get-Property $result 'ok'
    $report += "== $Project $Platform`: ok=$ok"
    $found = $false
    foreach ($step in @(Get-Property $result 'steps')) {
        if ($null -eq $step) { continue }
        foreach ($message in @(Get-Property $step 'messages')) {
            if ($null -eq $message) { continue }
            $found = $true
            $mark = Get-CaseMark ([string] $message.file) ([int] $message.line)
            $prefix = $(if ($mark) { "[$mark] " } else { '' })
            $report += "  $prefix[$($message.severity)] $(Split-Path -Leaf ([string] $message.file))" +
                "($($message.line)): $($message.code) $($message.text)"
        }
        $reason = Get-Property $step 'reason'
        if ($reason) { $report += "  ($reason)" }
    }
    if (-not $found) {
        if ($ok) {
            $report += '  (keine dcc-Meldung)'
        } else {
            # Ohne lesbare Meldungen die rohe Ausgabe des Bau-Skripts mitgeben.
            $report += '  (keine Meldung, Ausgabe des Bau-Skripts:)'
            $report += @($Build.Output -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | ForEach-Object { "    $_" })
        }
    }
    $report
}

foreach ($path in @($BuildScript, $GroupProject)) {
    if (-not (Test-Path $path)) {
        Write-Error "Nicht gefunden: $path" -ErrorAction Continue
        exit 3
    }
}

$projects = @(Get-ChildItem -Path $CaseDir -Filter '*.dproj' | Sort-Object Name)
$exitCode = 0
$report = @("dcc-Minimalfälle #1328, $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
try {
    foreach ($platform in $Platforms) {
        foreach ($project in $projects) {
            Write-Step "$($project.BaseName) bauen ($platform)"
            $build = Invoke-DelphiBuild $project.FullName $platform
            $report += Get-BuildReport $project.BaseName $platform $build
        }
    }
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 3
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultFile) | Out-Null
Set-Content -Path $ResultFile -Value $report -Encoding UTF8
$report | ForEach-Object { Write-Host $_ }
Write-Step "Ergebnis in $ResultFile"
exit $exitCode
