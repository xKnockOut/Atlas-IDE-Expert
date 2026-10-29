<#
.SYNOPSIS
    Bettet die HTML-Vorlagen der Architekturkarte (#1118) und des
    Aufrufdiagramms (#1122) als Pascal-Units ein.

.DESCRIPTION
    Quellen (HTML, CSS und Skript ohne externe Verweise):
    - Packages/Atlas.Common/Source/Architecture/Architekturkarte.html wird
      Atlas.Common.Architecture.MapTemplate mit der Funktion
      ArchitectureMapHtml; TArchitectureReport.Html setzt Titel ({{TITLE}})
      und Daten ({{DATA}}) ein.
    - Packages/Atlas.IDE.Expert/Source/Core/Results/Aufrufdiagramm.html wird
      Atlas.Core.Results.CallDiagramTemplate mit der Funktion
      CallDiagramHtml; TAtlasCallDiagram.Html setzt Titel und Daten ein.
    Jede Zeile der Vorlage wird ein Element eines Feldes, lange Zeilen in
    Stücken zu 200 Zeichen je Quelltextzeile (Delphi: höchstens 255 Zeichen je
    Literal, 1023 je Zeile).

    Mit -Check wird nichts geschrieben; Exit-Code 1, wenn die Unit veraltet ist
    oder ein Platzhalter fehlt.

.EXAMPLE
    pwsh Tools/Update-ArchitectureMap.ps1
    pwsh Tools/Update-ArchitectureMap.ps1 -Check
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Templates = @(
    @{ Folder = 'Packages/Atlas.Common/Source/Architecture'; Source = 'Architekturkarte.html';
       Unit = 'Atlas.Common.Architecture.MapTemplate'; Function = 'ArchitectureMapHtml';
       Purpose = 'Vorlage des HTML-Berichts der Architekturübersicht (#1118).' },
    @{ Folder = 'Packages/Atlas.IDE.Expert/Source/Core/Results'; Source = 'Aufrufdiagramm.html';
       Unit = 'Atlas.Core.Results.CallDiagramTemplate'; Function = 'CallDiagramHtml';
       Purpose = 'Vorlage des Aufrufdiagramms als HTML (#1122).' }
)
$Problems = New-Object System.Collections.Generic.List[string]

foreach ($Template in $Templates) {
$Folder = Join-Path $Root $Template.Folder
$SourcePath = Join-Path $Folder $Template.Source
$UnitPath = Join-Path $Folder ($Template.Unit + '.pas')
$Source = [IO.File]::ReadAllText($SourcePath, (New-Object System.Text.UTF8Encoding($false))).TrimStart([char]0xFEFF)
foreach ($Placeholder in @('{{TITLE}}', '{{DATA}}')) {
    if (-not $Source.Contains($Placeholder)) { $Problems.Add("$($Template.Source): Platzhalter $Placeholder fehlt") }
}
if ($Source -match '(src|href)\s*=\s*"(https?:)?//') { $Problems.Add("$($Template.Source): externer Verweis (die Seite muss offline laufen)") }

$Lines = $Source.Replace("`r`n", "`n").TrimEnd("`n").Split("`n")
$Text = New-Object System.Collections.Generic.List[string]
foreach ($Line in @(
    "unit $($Template.Unit);", '',
    "// Erzeugt von Tools/Update-ArchitectureMap.ps1 aus $($Template.Source);",
    "// nicht von Hand ändern. $($Template.Purpose)", '',
    'interface', '',
    "/// <summary>Inhalt von $($Template.Source) mit den Platzhaltern {{TITLE}} und {{DATA}}.</summary>",
    "function $($Template.Function): string;", '',
    'implementation', '', 'const',
    "  Lines: array[0..$($Lines.Count - 1)] of string = (")) { $Text.Add($Line) }
for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
    $Escaped = $Lines[$Index].Replace("'", "''")
    $Pieces = @()
    for ($At = 0; $At -lt $Escaped.Length; $At += 200) {
        $Length = [Math]::Min(200, $Escaped.Length - $At)
        # Ein verdoppeltes Hochkomma nicht zerschneiden.
        while ($Length -lt $Escaped.Length - $At -and $Escaped.Substring($At, $Length) -match "(^|[^'])('')*'$") { $Length-- }
        $Pieces += "'" + $Escaped.Substring($At, $Length) + "'"
        $At += $Length - 200
    }
    if ($Pieces.Count -eq 0) { $Pieces = @("''") }
    $End = if ($Index -eq $Lines.Count - 1) { ');' } else { ',' }
    $Text.Add('    ' + ($Pieces -join " +`r`n      ") + $End)
}
foreach ($Line in @('', "function $($Template.Function): string;", 'var', '  Line: string;', 'begin', "  Result := '';",
    '  for Line in Lines do', '    Result := Result + Line + #10;', 'end;', '', 'end.')) { $Text.Add($Line) }
$Result = ($Text -join "`r`n") + "`r`n"

$Current = if (Test-Path $UnitPath) { [IO.File]::ReadAllText($UnitPath).TrimStart([char]0xFEFF) } else { '' }
if ($Current.Replace("`r`n", "`n") -cne $Result.Replace("`r`n", "`n")) {
    if ($Check) { $Problems.Add("$($Template.Unit).pas ist veraltet: pwsh Tools/Update-ArchitectureMap.ps1 ausführen") }
    else {
        [IO.File]::WriteAllText($UnitPath, $Result, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "Geschrieben: $UnitPath"
    }
}
}
if ($Problems.Count -gt 0) {
    foreach ($Problem in $Problems) { Write-Host "FEHLER: $Problem" }
    exit 1
}
exit 0
