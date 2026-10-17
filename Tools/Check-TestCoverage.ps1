<#
.SYNOPSIS
    Prüft, dass jede Unit mit Logik eigene DUnitX-Tests hat und jede Testunit läuft (#415).

.DESCRIPTION
    1. Jede Unit unter Packages/Atlas.Text, Packages/Atlas.Common/Source,
       Packages/Atlas.Windows/Source, Packages/Atlas.IDE.Expert/Source/Core und
       Application/Source muss in einer Datei unter Tests/ vorkommen (in uses
       oder als Name ihrer Testunit "<Unit>.Tests"). Ausnahmen stehen unten mit
       Grund: dünne Adapter auf Betriebssystem, Netz oder Prozess, reine
       Verträge und erzeugte Units, die Update-ConfigDoc prüft.
    2. Jede Testunit Tests/**/*.Tests.pas muss in Tests/Atlas.Tests.dpr stehen,
       sonst läuft sie nie.
    3. Eine Ausnahme, die inzwischen Tests hat, ist zu streichen.

    IDE- und UI-Units (Packages/Atlas.IDE.Expert/Source/IDE, .../UI) brauchen die
    laufende IDE bzw. ein Fenster; ihre Logik gehört in den Kern (Core) und wird
    dort getestet.

    Exit-Code 0: alles in Ordnung, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-TestCoverage.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceDirs = @(
    'Packages/Atlas.Text',
    'Packages/Atlas.Common/Source',
    'Packages/Atlas.Windows/Source',
    'Packages/Atlas.IDE.Expert/Source/Core',
    'Application/Source'
)

# Unit → Grund. Nur, was sich ohne Betriebssystem, Netz oder IDE nicht sinnvoll prüfen lässt.
$Exempt = @{
    'Atlas.Windows.Editing.SystemColors'                = 'GetSysColor des laufenden Systems'
    'Atlas.Windows.Diagnostics.Adapters.DebugOutputSink' = 'schreibt nur über OutputDebugString'
    'Atlas.Windows.Diagnostics.ProcessInfo'             = 'liest Angaben des eigenen Prozesses vom System'
    'Atlas.Windows.Diagnostics.DebugOutput'             = 'Hülle um OutputDebugString'
    'Atlas.Windows.Process.ParentWatcher'               = 'wartet auf das Ende des Elternprozesses'
    'Atlas.Windows.Console.StdStreams'                  = 'Handles der Konsole (stdin/stdout)'
    'Atlas.Core.Files.Adapters.FolderWatcher'           = 'Ordnerbeobachtung des Systems (ReadDirectoryChangesW)'
    'Atlas.Core.Files.Contract'                         = 'nur Typen, ohne Logik'
    'Atlas.Core.Settings.PluginSchemaData'              = 'erzeugt; Update-ConfigDoc prüft sie gegen Schema und Parser'
    'Atlas.Core.Updates.Adapters.HttpSource'            = 'HTTP-Zugriff; die Auswertung testet Atlas.Core.Updates'
    'Atlas.Core.Ci.Adapters.Http'                       = 'HTTP-Zugriff; die Anbieter testen Atlas.Core.Ci.Providers.*'
    'Atlas.Core.Ci.Adapters.Credentials'                = 'Anmeldeinformationsverwaltung von Windows'
    'Shell.Application'                                 = 'Einstieg des Servers (Prozessstart, Konsole)'
}

$testFiles = Get-ChildItem -Path (Join-Path $Root 'Tests') -Recurse -File -Filter '*.pas'
$testText = ($testFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
$dpr = [IO.File]::ReadAllText((Join-Path $Root 'Tests/Atlas.Tests.dpr'))
$problems = @()

foreach ($dir in $SourceDirs) {
    $path = Join-Path $Root $dir
    if (-not (Test-Path $path)) { continue }
    foreach ($file in Get-ChildItem -Path $path -Recurse -File -Filter '*.pas') {
        $unit = $file.BaseName
        $pattern = '(?<![\w.])' + [regex]::Escape($unit) + '(\.Tests)?(?![\w.])'
        $tested = [regex]::IsMatch($testText, $pattern, 'IgnoreCase')
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
        if ($Exempt.ContainsKey($unit)) {
            if ($tested) { $problems += "${relative}: hat jetzt Tests, Ausnahme streichen" }
        } elseif (-not $tested) {
            $problems += "${relative}: keine Testunit nennt $unit"
        }
    }
}

foreach ($file in $testFiles | Where-Object { $_.Name -like '*.Tests.pas' }) {
    $unit = $file.BaseName
    if (-not [regex]::IsMatch($dpr, '(?m)^\s*' + [regex]::Escape($unit) + '\s+in\s', 'IgnoreCase')) {
        $problems += "$([IO.Path]::GetRelativePath($Root, $file.FullName)): fehlt in Tests/Atlas.Tests.dpr"
    }
}

if ($problems.Count -gt 0) {
    Write-Host 'Fehlende Tests (#415):' -ForegroundColor Red
    $problems | Sort-Object | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Jede Unit mit Logik hat Tests, jede Testunit läuft.' -ForegroundColor Green
exit 0
