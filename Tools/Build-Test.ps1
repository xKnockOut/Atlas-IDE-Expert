<#
.SYNOPSIS
    Baut die Projektgruppe über das IDE-Plugin cc.ps1 und führt die DUnitX-Tests aus (#260).

.DESCRIPTION
    Ersatz-CI für RAD Studio Starter (kein dcc/MSBuild auf der Kommandozeile),
    nach dem Ablauf in docs/Uebergabe.md:

    1. cc.ps1 start mit eigener Scratch-IDE; die pid wird aus der Ausgabe
       gelesen und muss zu einem neuen Prozess gehören. Jeder weitere Aufruf
       nutzt -Instance <pid>, eine schon laufende IDE bleibt unberührt.
    2. cc.ps1 group-build -Platform Win64 -Json: ok und outputWritten müssen
       gesetzt sein, die Test-exe und die Win64-Plugin-BPL für die 64-Bit-IDE
       müssen neu geschrieben sein und das logFile darf keine Hinweise oder
       Warnungen enthalten (0/0/0-Regel).
    3. Mit -Win32 zusätzlich Win32; dort darf nur Atlas.Tests scheitern
       (DUnitX gibt es nur für Win64, ADR 0008). Die Plugin-BPL für die
       klassische IDE muss dabei neu geschrieben sein (#78). Die BPL heißt
       wegen LIBSUFFIX AUTO je IDE-Version anders, z. B.
       Atlas.IDE.Expert370.bpl (#281).
    4. Atlas.Tests.exe --exitbehavior:Continue mit NUnit-XML als Ergebnis;
       die Benchmarks (Kategorie Benchmark, #415) nur mit -Benchmarks.
    5. cc.ps1 quit, wiederholt, solange die IDE beschäftigt ist.

    Exit-Code 0: alles grün. 1: Build-Fehler, Hinweis oder Warnung.
    2: Tests fehlgeschlagen. 3: Aufruf- oder Umgebungsfehler.

.EXAMPLE
    pwsh Tools/Build-Test.ps1
    pwsh Tools/Build-Test.ps1 -Win32 -ResultFile Output\dunitx.xml
    pwsh Tools/Build-Test.ps1 -Benchmarks
#>
[CmdletBinding()]
param(
    # Leer: Ordner über Tools. Windows PowerShell 5.1 kennt $PSScriptRoot im param-Block noch nicht.
    [string] $Root = '',
    [string] $CcScript = $(if ($env:CC_SCRIPT) { $env:CC_SCRIPT } else { 'C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1' }),
    [string] $Config = 'Debug',
    [switch] $Win32,
    [string] $ResultFile = 'dunitx-ergebnisse.xml',
    [switch] $SkipTests,
    [switch] $Benchmarks,
    [int] $QuitAttempts = 10,
    [int] $QuitDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

$GroupProject = Join-Path $Root 'Atlas.groupproj'
$TestExe = Join-Path $Root (Join-Path "Output/Win64/$Config/Bin" 'Atlas.Tests.exe')
# Plugin-BPL für die klassische (Win32) und die 64-Bit-IDE (Win64), ADR 0008.
# LIBSUFFIX AUTO hängt die Package-Version an: Atlas.IDE.Expert290.bpl (Delphi 12), …370.bpl (Delphi 13).
$PluginBplPattern = 'Atlas.IDE.Expert*.bpl'
# Zeilen des Build-Logs, die die 0/0/0-Regel verletzen, z. B. "[dcc64 Hinweis] X.pas(10): H2164 …".
$HintPattern = '\[dcc\w*\s+(Hinweis|Warnung|Hint|Warning)\]'
$ErrorPattern = '\[dcc\w*\s+(Fehler|Schwerwiegend|Error|Fatal)\]'

function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

# Prüft, dass die Plugin-BPL der Plattform seit $Started neu geschrieben wurde.
function Test-PluginBpl([string] $Platform, [datetime] $Started) {
    $dir = Join-Path $Root "Output/$Platform/$Config/Bpl"
    $bpl = @(Get-ChildItem -Path $dir -Filter $PluginBplPattern -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending) | Select-Object -First 1
    if ($null -eq $bpl) {
        return "${Platform}: Plugin-BPL fehlt: $dir\$PluginBplPattern"
    }
    if ($bpl.LastWriteTime -lt $Started) {
        return "${Platform}: Plugin-BPL wurde nicht neu geschrieben (von einer IDE geladen? ADR 0006): $($bpl.FullName)"
    }
    return $null
}

function Get-IdeProcessIds {
    @(Get-Process -Name 'bds' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
}

function Invoke-Cc([string[]] $Arguments) {
    # Benannte Parameter als Hashtable: Beim Splatting eines Arrays käme "-Project" als Wert an
    # ("kein Positionsparameter … akzeptiert das Argument -Project"), wie in Build-DccFaelle.ps1.
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

# outputWritten steht oben im JSON oder (neuere cc.ps1) nur je Schritt unter steps[].
function Test-OutputWritten($Result) {
    $top = Get-Property $Result 'outputWritten'
    if ($null -ne $top) { return [bool] $top }
    $flags = @(@(Get-Property $Result 'steps') | Where-Object { $null -ne $_ } |
        ForEach-Object { Get-Property $_ 'outputWritten' } | Where-Object { $null -ne $_ })
    ($flags.Count -gt 0) -and -not ($flags -contains $false)
}

# Liest die JSON-Antwort von group-build; cc.ps1 kann davor Text ausgeben.
function ConvertFrom-BuildOutput([string] $Output) {
    $start = $Output.IndexOf('{')
    if ($start -lt 0) { throw "group-build lieferte kein JSON:`n$Output" }
    $Output.Substring($start) | ConvertFrom-Json
}

function Get-Property($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null }
}

# Prüft einen Gruppen-Build; liefert die Liste der Verstöße (leer = in Ordnung).
function Test-Build($Result, [string] $Platform, [datetime] $Started, [bool] $TestsMayFail) {
    $problems = @()
    $logFile = Get-Property $Result 'logFile'
    $logLines = @()
    if ($logFile -and (Test-Path $logFile)) { $logLines = @(Get-Content -Path $logFile) }
    foreach ($line in $logLines) {
        if ($line -match $HintPattern) { $problems += "$Platform`: $line" }
    }
    $errors = @($logLines | Where-Object { $_ -match $ErrorPattern })
    if ($TestsMayFail) {
        # Win32: nur Fehler im Testprojekt sind erwartet (DUnitX fehlt dort).
        foreach ($line in $errors) {
            if ($line -notmatch 'Atlas\.Tests|[\\/]Tests[\\/]') { $problems += "$Platform`: $line" }
        }
    } else {
        foreach ($line in $errors) { $problems += "$Platform`: $line" }
        if (-not (Get-Property $Result 'ok')) { $problems += "$Platform`: group-build meldet ok = false" }
        if (-not (Test-OutputWritten $Result)) { $problems += "$Platform`: keine Ausgabe geschrieben (outputWritten)" }
    }
    $problems
}

if (-not (Test-Path $CcScript)) {
    Write-Error "cc.ps1 nicht gefunden: $CcScript (Parameter -CcScript oder Umgebungsvariable CC_SCRIPT)" -ErrorAction Continue
    exit 3
}
if (-not (Test-Path $GroupProject)) {
    Write-Error "Projektgruppe nicht gefunden: $GroupProject" -ErrorAction Continue
    exit 3
}

$exitCode = 0
$ideId = $null
$before = Get-IdeProcessIds
try {
    Write-Step 'Scratch-IDE starten'
    $start = Invoke-Cc @('start', '-Project', $GroupProject)
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

    $problems = @()
    Write-Step 'Projektgruppe bauen (Win64)'
    $started = Get-Date
    $build = Invoke-Cc @('group-build', '-Instance', "$ideId", '-Platform', 'Win64', '-Json')
    Write-Host $build.Output
    $result = ConvertFrom-BuildOutput $build.Output
    $problems += Test-Build $result 'Win64' $started $false
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
        $build32 = Invoke-Cc @('group-build', '-Instance', "$ideId", '-Platform', 'Win32', '-Json')
        Write-Host $build32.Output
        $problems += Test-Build (ConvertFrom-BuildOutput $build32.Output) 'Win32' $started32 $true
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
exit $exitCode
