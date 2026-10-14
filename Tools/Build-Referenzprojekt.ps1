<#
.SYNOPSIS
    Baut das Referenz-Testprojekt über cc.ps1 für Win32 und Win64 und prüft die gewollten Meldungen (#94).

.DESCRIPTION
    Ablauf wie Tools/Build-Test.ps1 (#260), aber für Tests/Referenzprojekt:

    1. cc.ps1 start mit RefGruppe.groupproj in einer eigenen Scratch-IDE; die pid
       muss zu einem neuen Prozess gehören.
    2. cc.ps1 group-build je Plattform (Vorgabe Win32 und Win64): ok und
       outputWritten müssen gesetzt sein.
    3. Hinweise und Warnungen im logFile werden mit erwartete-meldungen.txt
       verglichen: Jede Zeile der Liste muss je Plattform genau einmal kommen,
       jede andere Meldung lässt den Build scheitern.
    4. Mit -MitDaten zusätzlich das optionale Projekt RefDaten (FireDAC) über
       cc.ps1 build; dort gelten dieselbe Liste und dieselben Regeln.
    5. cc.ps1 quit, wiederholt, solange die IDE beschäftigt ist.
    6. Die .dproj- und .groupproj-Dateien dürfen sich dabei nicht ändern; sonst
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
    [string] $CcScript = $(if ($env:CC_SCRIPT) { $env:CC_SCRIPT } else { 'C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1' }),
    [string[]] $Platforms = @('Win32', 'Win64'),
    [switch] $MitDaten,
    # Zusätzliche Argumente für "cc.ps1 start", etwa für eine andere Delphi-Version (Delphi 12, #281),
    # sofern cc.ps1 sie anbietet.
    [string[]] $CcStartArguments = @(),
    [int] $QuitAttempts = 10,
    [int] $QuitDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectDir = Join-Path $Root 'Tests/Referenzprojekt'
$GroupProject = Join-Path $ProjectDir 'RefGruppe.groupproj'
$DataProject = Join-Path $ProjectDir 'RefDaten.dproj'
$ExpectedFile = Join-Path $ProjectDir 'erwartete-meldungen.txt'
# "[dcc64 Hinweis] X.pas(10): H2164 Variable 'Unbenutzt' …"
$MessagePattern = '\[dcc\w*\s+(Hinweis|Warnung|Hint|Warning)\]\s*(?:.*[\\/])?([\w.]+\.(?:pas|dpr|dpk|inc))\(\d+\)\s*:?\s*([HW]\d{4})\s*(.*)$'
$AnyMessagePattern = '\[dcc\w*\s+(Hinweis|Warnung|Hint|Warning)\]'
$ErrorPattern = '\[dcc\w*\s+(Fehler|Schwerwiegend|Error|Fatal)\]'

function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

function Get-IdeProcessIds {
    @(Get-Process -Name 'bds' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
}

function Invoke-Cc([string[]] $Arguments) {
    $output = & $CcScript @Arguments 2>&1 | Out-String
    [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

function ConvertFrom-BuildOutput([string] $Output) {
    $start = $Output.IndexOf('{')
    if ($start -lt 0) { throw "cc.ps1 lieferte kein JSON:`n$Output" }
    $Output.Substring($start) | ConvertFrom-Json
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

# Vergleicht die Meldungen eines Build-Logs mit der Liste; liefert die Verstöße (leer = in Ordnung).
function Test-Messages([string[]] $LogLines, $Expected, [string] $Label) {
    $problems = @()
    $counts = @{}
    foreach ($line in $LogLines) {
        if ($line -match $ErrorPattern) {
            $problems += "$Label`: $line"
            continue
        }
        if ($line -notmatch $AnyMessagePattern) { continue }
        $match = $null
        if ($line -match $MessagePattern) {
            $file = $Matches[2]; $code = $Matches[3]; $text = $Matches[4]
            $match = $Expected | Where-Object {
                $_.File -eq $file -and $_.Code -eq $code -and $text -match ("'" + [regex]::Escape($_.Name) + "'")
            } | Select-Object -First 1
        }
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
    if (-not (Get-Property $Result 'ok')) { $problems += "$Label`: cc.ps1 meldet ok = false" }
    if (-not (Get-Property $Result 'outputWritten')) { $problems += "$Label`: keine Ausgabe geschrieben (outputWritten)" }
    $logFile = Get-Property $Result 'logFile'
    if (-not $logFile -or -not (Test-Path $logFile)) {
        $problems += "$Label`: kein Build-Log (logFile)"
    } else {
        $problems += Test-Messages @(Get-Content -Path $logFile) $Expected $Label
    }
    $problems
}

function Get-ProjectFileHashes {
    $hashes = @{}
    Get-ChildItem -Path $ProjectDir -File | Where-Object { $_.Extension -in '.dproj', '.groupproj' } | ForEach-Object {
        $hashes[$_.Name] = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    }
    $hashes
}

foreach ($path in @($CcScript, $GroupProject, $ExpectedFile)) {
    if (-not (Test-Path $path)) {
        Write-Error "Nicht gefunden: $path" -ErrorAction Continue
        exit 3
    }
}

$exitCode = 0
$ideId = $null
$problems = @()
$hashesBefore = Get-ProjectFileHashes
$before = Get-IdeProcessIds
try {
    $expected = @(Read-ExpectedMessages $ExpectedFile)

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

    foreach ($platform in $Platforms) {
        Write-Step "RefGruppe bauen ($platform)"
        $build = Invoke-Cc @('group-build', '-Instance', "$ideId", '-Platform', $platform, '-Json')
        Write-Host $build.Output
        $problems += Test-Build (ConvertFrom-BuildOutput $build.Output) $expected "RefGruppe $platform"
        if ($MitDaten) {
            Write-Step "RefDaten bauen ($platform)"
            $data = Invoke-Cc @('build', '-Instance', "$ideId", '-Project', $DataProject, '-Platform', $platform, '-Json')
            Write-Host $data.Output
            $problems += Test-Build (ConvertFrom-BuildOutput $data.Output) $expected "RefDaten $platform"
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
