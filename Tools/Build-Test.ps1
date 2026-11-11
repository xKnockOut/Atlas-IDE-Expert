<#
.SYNOPSIS
    Baut die Projektgruppe über ein externes Delphi-Bau-Skript und führt die DUnitX-Tests aus (#260, #1904).

.DESCRIPTION
    Die Gruppe enthält das Atlas-Plugin selbst; Tools/Build-Ide.ps1 kann sie
    deshalb nicht bauen (die Bau-IDE würde das Plugin entladen). Gebaut wird
    über das Skript in der Umgebungsvariablen ATLAS_DELPHI_BUILD (oder
    -BuildScript). Es nimmt dieselben Parameter wie Tools/Build-Ide.ps1
    (-Project, -Platform, -Mode, -Json) und liefert dasselbe JSON:
    {"ok", "summary": {fatals, errors, warnings, hints},
     "steps": [{project, ok, summary, messages[{file, line, column, severity, code, text}]}]}.

    1. Projektgruppe Win64 bauen: ok gesetzt, 0 Fehler, 0 Warnungen,
       0 Hinweise; die Test-exe und die Win64-Plugin-BPL für die 64-Bit-IDE
       müssen neu geschrieben sein.
    2. Mit -Win32 zusätzlich Win32; dort darf nur Atlas.Tests scheitern
       (DUnitX gibt es nur für Win64). Die Plugin-BPL für die klassische IDE
       muss dabei neu geschrieben sein (#78). Die BPL heißt wegen LIBSUFFIX
       AUTO je IDE-Version anders, z. B. Atlas.IDE.Base370.bpl (#281).
    3. Atlas.Tests.exe --exitbehavior:Continue mit NUnit-XML als Ergebnis;
       die Benchmarks (Kategorie Benchmark, #415) nur mit -Benchmarks.

    Exit-Code 0: alles grün. 1: Build-Fehler, Hinweis oder Warnung.
    2: Tests fehlgeschlagen. 3: Aufruf- oder Umgebungsfehler (auch ohne
    ATLAS_DELPHI_BUILD).

.EXAMPLE
    pwsh Tools/Build-Test.ps1
    pwsh Tools/Build-Test.ps1 -Win32 -ResultFile Output\dunitx.xml
    pwsh Tools/Build-Test.ps1 -Benchmarks
#>
[CmdletBinding()]
param(
    # Leer: Ordner über Tools. Windows PowerShell 5.1 kennt $PSScriptRoot im param-Block noch nicht.
    [string] $Root = '',
    # Externes Bau-Skript (Parameter wie Tools/Build-Ide.ps1); Vorgabe aus ATLAS_DELPHI_BUILD.
    [string] $BuildScript = $env:ATLAS_DELPHI_BUILD,
    [string] $Config = 'Debug',
    [switch] $Win32,
    # Leer: Output/dunitx-ergebnisse.xml unter $Root.
    [string] $ResultFile = '',
    [switch] $SkipTests,
    [switch] $Benchmarks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
# Der XML-Logger von DUnitX legt den Ordner der Datei an und scheitert bei einem Namen ohne Ordner
# (EInOutError "Verzeichnis kann nicht erstellt werden"): immer einen vollen Pfad übergeben.
if (-not $ResultFile) { $ResultFile = Join-Path $Root 'Output/dunitx-ergebnisse.xml' }
if (-not [System.IO.Path]::IsPathRooted($ResultFile)) { $ResultFile = Join-Path (Get-Location).Path $ResultFile }

$GroupProject = Join-Path $Root 'Atlas.groupproj'
$TestExe = Join-Path $Root (Join-Path "Output/Win64/$Config/Bin" 'Atlas.Tests.exe')
# Plugin-BPLs für die klassische (Win32) und die 64-Bit-IDE (Win64): das Kern-Package und jedes
# Modul-Package unter Packages/Atlas.IDE.* (#1456). LIBSUFFIX AUTO hängt die Package-Version an:
# Atlas.IDE.Base290.bpl (Delphi 12), …370.bpl (Delphi 13).
$PluginPackages = @(Get-ChildItem -Path (Join-Path $Root 'Packages') -Directory -Filter 'Atlas.IDE.*' |
    Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).dpk") } | ForEach-Object Name | Sort-Object)
function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

# Prüft, dass jede Plugin-BPL der Plattform seit $Started neu geschrieben wurde; liefert die erste Abweichung.
function Test-PluginBpl([string] $Platform, [datetime] $Started) {
    $dir = Join-Path $Root "Output/$Platform/$Config/Bpl"
    foreach ($package in $PluginPackages) {
        # Name, Versionsnummer, .bpl: "Atlas.IDE.Base370.bpl" passt zu Atlas.IDE.Base, nicht zu Atlas.IDE.Base.X.
        $bpl = @(Get-ChildItem -Path $dir -Filter "$package*.bpl" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match ('^' + [regex]::Escape($package) + '\d*$') } |
            Sort-Object LastWriteTime -Descending) | Select-Object -First 1
        if ($null -eq $bpl) {
            return "${Platform}: Plugin-BPL fehlt: $dir\$package*.bpl"
        }
        if ($bpl.LastWriteTime -lt $Started) {
            return "${Platform}: Plugin-BPL wurde nicht neu geschrieben (von einer IDE geladen?): $($bpl.FullName)"
        }
    }
    return $null
}

# Baut $Project über das externe Skript und liefert dessen JSON-Antwort.
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

# Prüft einen Gruppen-Build nach der 0/0/0-Regel; liefert die Liste der Verstöße (leer = in Ordnung).
function Test-Build($Result, [string] $Platform, [bool] $TestsMayFail) {
    $problems = @()
    foreach ($step in @(Get-Property $Result 'steps')) {
        if ($null -eq $step) { continue }
        $isTests = [string] (Get-Property $step 'project') -match 'Atlas\.Tests'
        foreach ($message in @(Get-Property $step 'messages')) {
            if ($null -eq $message) { continue }
            $line = "$Platform`: [$($message.severity)] $($message.file)($($message.line)): $($message.code) $($message.text)"
            if ($message.severity -match '^(hint|warning)') { $problems += $line }
            elseif (-not ($TestsMayFail -and $isTests)) { $problems += $line }
        }
        $reason = Get-Property $step 'reason'
        if (-not (Get-Property $step 'ok') -and -not ($TestsMayFail -and $isTests)) {
            $problems += "$Platform`: $(Get-Property $step 'project') nicht gebaut $reason"
        }
    }
    if (-not $TestsMayFail -and -not (Get-Property $Result 'ok')) { $problems += "$Platform`: Bau meldet ok = false" }
    $problems
}

if (-not $BuildScript) {
    Write-Error ('Kein Delphi-Bau-Skript: ATLAS_DELPHI_BUILD (oder -BuildScript) auf ein Skript mit den ' +
        'Parametern von Tools/Build-Ide.ps1 setzen. Die Gruppe enthält das Plugin und lässt sich deshalb nicht ' +
        'über Tools/Build-Ide.ps1 bauen.') -ErrorAction Continue
    exit 3
}
if (-not (Test-Path $BuildScript)) {
    Write-Error "Bau-Skript nicht gefunden: $BuildScript" -ErrorAction Continue
    exit 3
}
if (-not (Test-Path $GroupProject)) {
    Write-Error "Projektgruppe nicht gefunden: $GroupProject" -ErrorAction Continue
    exit 3
}

$exitCode = 0
try {
    $problems = @()
    Write-Step 'Projektgruppe bauen (Win64)'
    $started = Get-Date
    $result = Invoke-DelphiBuild $GroupProject 'Win64'
    $problems += Test-Build $result 'Win64' $false
    if (-not (Test-Path $TestExe)) {
        $problems += "Win64: Test-exe fehlt: $TestExe"
    } elseif ((Get-Item $TestExe).LastWriteTime -lt $started) {
        $problems += "Win64: Test-exe wurde nicht neu geschrieben: $TestExe"
    }
    $pluginProblem = Test-PluginBpl 'Win64' $started
    if ($pluginProblem) { $problems += $pluginProblem }

    if ($Win32) {
        Write-Step 'Projektgruppe bauen (Win32, ohne Testprojekt)'
        $started32 = Get-Date
        $problems += Test-Build (Invoke-DelphiBuild $GroupProject 'Win32') 'Win32' $true
        $pluginProblem = Test-PluginBpl 'Win32' $started32
        if ($pluginProblem) { $problems += $pluginProblem }
    }

    if ($problems.Count -gt 0) {
        Write-Step 'Build verletzt die 0/0/0-Regel'
        $problems | ForEach-Object { Write-Host "  $_" }
        $exitCode = 1
    } elseif (-not $SkipTests) {
        Write-Step 'DUnitX-Tests ausführen'
        # Benchmarks laufen getrennt von den Funktionstests (#415), wie Tests\Tests.bat.
        $filter = '--exclude:Benchmark'
        if ($Benchmarks) { $filter = '--include:Benchmark' }
        & $TestExe $filter '--exitbehavior:Continue' "--xmlfile:$ResultFile"
        if ($LASTEXITCODE -ne 0) {
            Write-Step "Tests fehlgeschlagen (Exit-Code $LASTEXITCODE)"
            $exitCode = 2
        } else {
            Write-Step 'Build und Tests grün'
        }
    }
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 3
}
exit $exitCode
