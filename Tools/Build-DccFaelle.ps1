<#
.SYNOPSIS
    Übersetzt die dcc-Minimalfälle aus Tests/DccFaelle über cc.ps1 und schreibt alle dcc-Meldungen in eine Datei (#1328).

.DESCRIPTION
    Die Fälle zeigen, welche Muster Delphi annimmt und welche es meldet. Danach
    richten sich die Compilerregeln („wie Exxxx“), damit Atlas nicht strenger
    meldet als dcc. Jedes Projekt wird einzeln gebaut, damit ein Fehler in einem
    Fall die anderen nicht verdeckt. Projekte ohne „Gegen“ sollen sauber
    übersetzen, Projekte mit „Gegen“ enthalten Fälle, die dcc vermutlich meldet.

    1. cc.ps1 start mit DccFaelle.groupproj in einer eigenen Scratch-IDE; die pid
       muss zu einem neuen Prozess gehören.
    2. cc.ps1 build je Projekt und Plattform (Vorgabe Win32 und Win64).
    3. Aus dem logFile jede dcc-Zeile übernehmen, dazu die Fallmarke (// PA1 …)
       aus der gemeldeten Quellzeile.
    4. cc.ps1 quit, wiederholt, solange die IDE beschäftigt ist.

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
    [string] $CcScript = $(if ($env:CC_SCRIPT) { $env:CC_SCRIPT } else { 'C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1' }),
    [string[]] $Platforms = @('Win32', 'Win64'),
    # Zusätzliche Argumente für "cc.ps1 start", etwa für eine andere Delphi-Version (Delphi 12, #281),
    # sofern cc.ps1 sie anbietet.
    [string[]] $CcStartArguments = @(),
    [int] $QuitAttempts = 10,
    [int] $QuitDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CaseDir = Join-Path $Root 'Tests/DccFaelle'
$GroupProject = Join-Path $CaseDir 'DccFaelle.groupproj'
$ResultFile = Join-Path $Root 'Output/DccFaelle-Ergebnis.txt'
$DccPattern = '\[dcc\w*\s+[^\]]+\]'
# "[dcc32 Fehler] Dcc.Inline.pas(23): E2358 …"
$LocationPattern = '([\w.]+\.(?:pas|dpr|inc))\((\d+)\)'

function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

function Get-IdeProcessIds {
    @(Get-Process -Name 'bds' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
}

function Invoke-Cc([string[]] $Arguments) {
    # Benannte Parameter als Hashtable: Beim Splatting eines Arrays käme "-Project" als Wert an.
    $named = @{}
    $positional = @()
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -match '^-(\w+)$') {
            if ($i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-\w+$') {
                $named[$Matches[1]] = $Arguments[$i + 1]
                $i++
            } else {
                $named[$Matches[1]] = $true
            }
        } else {
            $positional += $arg
        }
    }
    # StrictMode dieses Skripts nicht an cc.ps1 vererben (liest optionale Felder aus status.json).
    $output = & { Set-StrictMode -Off; & $CcScript @positional @named } *>&1 | Out-String
    [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

function ConvertFrom-BuildOutput([string] $Output) {
    $start = $Output.IndexOf('{')
    if ($start -lt 0) { return $null }
    try { $Output.Substring($start) | ConvertFrom-Json } catch { $null }
}

function Get-Property($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null }
}

# Liefert die Fallmarke (PA1, IV2 …) aus der Quellzeile einer Meldung, sonst ''.
function Get-CaseMark([string] $Line) {
    if ($Line -notmatch $LocationPattern) { return '' }
    $path = Join-Path $CaseDir $Matches[1]
    $number = [int] $Matches[2]
    if (-not (Test-Path $path)) { return '' }
    $lines = @(Get-Content -Path $path -Encoding UTF8)
    if ($number -lt 1 -or $number -gt $lines.Count) { return '' }
    if ($lines[$number - 1] -match '//\s*([A-Z]{2}\d+)') { return $Matches[1] }
    ''
}

function Get-BuildReport([string] $Project, [string] $Platform, $Build) {
    $report = @()
    $result = ConvertFrom-BuildOutput $Build.Output
    $ok = Get-Property $result 'ok'
    $report += "== $Project $Platform`: ok=$ok"
    $logFile = Get-Property $result 'logFile'
    $found = $false
    if ($logFile -and (Test-Path $logFile)) {
        foreach ($line in Get-Content -Path $logFile) {
            if ($line -notmatch $DccPattern) { continue }
            $found = $true
            $mark = Get-CaseMark $line
            $prefix = $(if ($mark) { "[$mark] " } else { '' })
            $report += "  $prefix$($line.Trim())"
        }
    }
    if (-not $found) {
        if ($ok) {
            $report += '  (keine dcc-Meldung)'
        } else {
            # Das Plugin kann die Fehlertexte nicht immer lesen; dann die rohe Ausgabe mitgeben.
            $report += '  (keine dcc-Zeile im Log, Ausgabe von cc.ps1:)'
            $report += @($Build.Output -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | ForEach-Object { "    $_" })
        }
    }
    $report
}

foreach ($path in @($CcScript, $GroupProject)) {
    if (-not (Test-Path $path)) {
        Write-Error "Nicht gefunden: $path" -ErrorAction Continue
        exit 3
    }
}

$projects = @(Get-ChildItem -Path $CaseDir -Filter '*.dproj' | Sort-Object Name)
$exitCode = 0
$ideId = $null
$report = @("dcc-Minimalfälle #1328, $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$before = Get-IdeProcessIds
try {
    Write-Step 'Scratch-IDE starten'
    $start = Invoke-Cc (@('start', '-Project', $GroupProject) + $CcStartArguments)
    Write-Host $start.Output
    if ($start.Output -notmatch 'pid\D*(\d+)') {
        Write-Error 'pid der Scratch-IDE nicht in der Ausgabe von cc.ps1 start gefunden' -ErrorAction Continue
        exit 3
    }
    $ideId = [int] $Matches[1]
    # Nie in eine schon laufende IDE bauen, etwa die des Benutzers.
    if ($before -contains $ideId) {
        Write-Error "pid $ideId gehört zu einer schon laufenden IDE; Abbruch, um sie nicht zu benutzen" -ErrorAction Continue
        $ideId = $null
        exit 3
    }
    $report += "IDE: $(($start.Output -split "`r?`n" | Where-Object { $_ -match 'BDS|Delphi|Version|37\.0|23\.0' } | Select-Object -First 1))"

    foreach ($platform in $Platforms) {
        foreach ($project in $projects) {
            Write-Step "$($project.BaseName) bauen ($platform)"
            $build = Invoke-Cc @('build', '-Instance', "$ideId", '-Project', $project.FullName, '-Platform', $platform, '-Json')
            $report += Get-BuildReport $project.BaseName $platform $build
        }
    }
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 3
} finally {
    if ($null -ne $ideId) {
        Write-Step 'Scratch-IDE beenden'
        for ($attempt = 1; $attempt -le $QuitAttempts; $attempt++) {
            $quit = Invoke-Cc @('quit', '-Instance', "$ideId")
            if ($quit.ExitCode -eq 0) { break }
            Write-Host "IDE noch beschäftigt, Versuch $attempt von $QuitAttempts"
            Start-Sleep -Seconds $QuitDelaySeconds
        }
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultFile) | Out-Null
Set-Content -Path $ResultFile -Value $report -Encoding UTF8
$report | ForEach-Object { Write-Host $_ }
Write-Step "Ergebnis in $ResultFile"
exit $exitCode
