<#
.SYNOPSIS
    Bettet die Vorlage der Architekturkarte (#1118) als Pascal-Unit ein.

.DESCRIPTION
    Quelle ist Packages/Atlas.Common/Source/Architecture/Architekturkarte.html
    (HTML, CSS und Skript ohne externe Verweise). Daraus entsteht
    Atlas.Common.Architecture.MapTemplate mit der Funktion ArchitectureMapHtml;
    TArchitectureReport.Html setzt Titel ({{TITLE}}) und Daten ({{DATA}}) ein.
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

$Folder = Join-Path $Root 'Packages/Atlas.Common/Source/Architecture'
$SourcePath = Join-Path $Folder 'Architekturkarte.html'
$UnitPath = Join-Path $Folder 'Atlas.Common.Architecture.MapTemplate.pas'
$Source = [IO.File]::ReadAllText($SourcePath, (New-Object System.Text.UTF8Encoding($false))).TrimStart([char]0xFEFF)
$Problems = New-Object System.Collections.Generic.List[string]
foreach ($Placeholder in @('{{TITLE}}', '{{DATA}}')) {
    if (-not $Source.Contains($Placeholder)) { $Problems.Add("Architekturkarte.html: Platzhalter $Placeholder fehlt") }
}
if ($Source -match '(src|href)\s*=\s*"(https?:)?//') { $Problems.Add('Architekturkarte.html: externer Verweis (die Seite muss offline laufen)') }

$Lines = $Source.Replace("`r`n", "`n").TrimEnd("`n").Split("`n")
$Text = New-Object System.Collections.Generic.List[string]
foreach ($Line in @(
    'unit Atlas.Common.Architecture.MapTemplate;', '',
    '// Erzeugt von Tools/Update-ArchitectureMap.ps1 aus Architekturkarte.html;',
    '// nicht von Hand ändern. Vorlage des HTML-Berichts der Architekturübersicht (#1118).', '',
    'interface', '',
    '/// <summary>Inhalt von Architekturkarte.html mit den Platzhaltern {{TITLE}} und {{DATA}}.</summary>',
    'function ArchitectureMapHtml: string;', '',
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
foreach ($Line in @('', 'function ArchitectureMapHtml: string;', 'var', '  Line: string;', 'begin', "  Result := '';",
    '  for Line in Lines do', '    Result := Result + Line + #10;', 'end;', '', 'end.')) { $Text.Add($Line) }
$Result = ($Text -join "`r`n") + "`r`n"

$Current = if (Test-Path $UnitPath) { [IO.File]::ReadAllText($UnitPath).TrimStart([char]0xFEFF) } else { '' }
if ($Current.Replace("`r`n", "`n") -cne $Result.Replace("`r`n", "`n")) {
    if ($Check) { $Problems.Add('Atlas.Common.Architecture.MapTemplate.pas ist veraltet: pwsh Tools/Update-ArchitectureMap.ps1 ausführen') }
    else {
        [IO.File]::WriteAllText($UnitPath, $Result, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "Geschrieben: $UnitPath"
    }
}
if ($Problems.Count -gt 0) {
    foreach ($Problem in $Problems) { Write-Host "FEHLER: $Problem" }
    exit 1
}
exit 0
