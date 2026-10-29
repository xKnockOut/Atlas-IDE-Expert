<#
.SYNOPSIS
    Macht aus einem Absturzfall des Servers eine DUnitX-Testunit (#1355).

.DESCRIPTION
    Ein Absturzfall liegt unter %LOCALAPPDATA%\Atlas\crash\<Zeitpunkt>_<pid>\
    (anfrage.json, Schnappschuss der Datei, Einstellungen ohne Zugangsdaten,
    stapel.txt). Das Skript bettet anfrage.json und die Dateien daneben als
    Zeichenketten in eine Testunit ein und trägt sie in Tests/Atlas.Tests.dpr
    und Tests/Atlas.Tests.dproj ein:

        Tests/Application/Shell/CrashCases/Shell.CrashCase.<Name>.Tests.pas

    Der Test stellt den Fall isoliert mit dem vollständigen Server nach
    (TCrashReplayTest aus Shell.ReplayServer.Tests, wie AtlasServer --replay)
    und erwartet „nicht reproduziert“: Nach der Behebung bleibt er als
    Regressionstest stehen. Vor der Behebung schlägt er fehl.

    Zeilen der eingebetteten Dateien werden auf höchstens 200 Zeichen je
    Literal umbrochen (Delphi: F2069 ab 1024 Zeichen je Zeile).

    Exit-Code 0: Testunit angelegt, 1: Fehler.

.PARAMETER Case
    Ordner des Falls oder sein anfrage.json.

.PARAMETER Name
    Name im Unitnamen (Buchstaben, Ziffern); ohne Angabe aus dem Ordnernamen.

.EXAMPLE
    pwsh Tools/New-CrashTest.ps1 "$env:LOCALAPPDATA\Atlas\crash\2026-10-29_211530_4711" -Name HoverAuftrag
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Case,
    [string] $Name = '',
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MaxChunk = 200
$Utf8Bom = [Text.UTF8Encoding]::new($true)

function ConvertTo-DelphiLiteral([string] $Text, [string] $Indent) {
    # Jede Quellzeile wird zu '...'#13#10 + , lange Zeilen in Stücke zu höchstens $MaxChunk Zeichen.
    $parts = [Collections.Generic.List[string]]::new()
    $lines = $Text -split "`r?`n", -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $last = $i -eq $lines.Count - 1
        if ($last -and $line -eq '') { break }
        $chunks = @()
        if ($line.Length -eq 0) { $chunks = @('') }
        for ($p = 0; $p -lt $line.Length; $p += $MaxChunk) {
            $chunks += $line.Substring($p, [Math]::Min($MaxChunk, $line.Length - $p))
        }
        for ($c = 0; $c -lt $chunks.Count; $c++) {
            $literal = "'" + $chunks[$c].Replace("'", "''").Replace("`t", "'#9'") + "'"
            if ($c -eq $chunks.Count - 1 -and -not $last) { $literal += '#13#10' }
            $parts.Add($literal)
        }
    }
    if ($parts.Count -eq 0) { return "''" }
    return ($parts -join (" +`r`n" + $Indent))
}

$requestFile = $Case
if (Test-Path -LiteralPath $Case -PathType Container) {
    $requestFile = Join-Path $Case 'anfrage.json'
}
if (-not (Test-Path -LiteralPath $requestFile -PathType Leaf)) {
    Write-Error "Kein Absturzfall: $requestFile fehlt"
    exit 1
}
$folder = Split-Path -Parent (Resolve-Path -LiteralPath $requestFile)
$requestText = [IO.File]::ReadAllText($requestFile)
$request = $requestText | ConvertFrom-Json

if ($Name -eq '') {
    $Name = 'Fall' + ((Split-Path -Leaf $folder) -replace '[^A-Za-z0-9]', '')
}
if ($Name -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
    Write-Error "Name '$Name': nur Buchstaben und Ziffern, mit einem Buchstaben vorn"
    exit 1
}

# Dateien daneben, wie anfrage.json sie nennt (TCrashCases.Load liest dieselben).
$files = [Collections.Generic.List[string]]::new()
if ($request.PSObject.Properties.Name -contains 'files') {
    $list = $request.files
    if ($list.PSObject.Properties.Name -contains 'snapshot') { $files.Add([IO.Path]::GetFileName($list.snapshot)) }
    if ($list.PSObject.Properties.Name -contains 'settings') {
        foreach ($setting in $list.settings) { $files.Add([IO.Path]::GetFileName($setting)) }
    }
}

$unit = "Shell.CrashCase.$Name.Tests"
$fixture = "TCrashCase${Name}Tests"
$relativeDir = 'Application\Shell\CrashCases'
$target = Join-Path $Root (Join-Path 'Tests' ($relativeDir -replace '\\', [IO.Path]::DirectorySeparatorChar))
$targetFile = Join-Path $target "$unit.pas"
if (Test-Path -LiteralPath $targetFile) {
    Write-Error "$targetFile gibt es schon; anderen Namen wählen (-Name)"
    exit 1
}

$indent = '      '
$fileArgs = @()
foreach ($file in $files) {
    $path = Join-Path $folder $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = [IO.File]::ReadAllText($path)
    $fileArgs += "    TCrashReplayFile.Create('$($file.Replace("'", "''"))',`r`n$indent" + (ConvertTo-DelphiLiteral $text $indent) + ')'
}
$filesExpr = 'nil'
if ($fileArgs.Count -gt 0) {
    $filesExpr = "TArray<TCrashReplayFile>.Create(`r`n" + ($fileArgs -join ",`r`n") + ')'
}
$summary = "$($request.method)"
if ($request.PSObject.Properties.Name -contains 'exception') { $summary += " ($($request.exception.class))" }

$source = @"
unit $unit;

// Regressionstest aus dem Absturzfall $(Split-Path -Leaf $folder) (#1355,
// erzeugt mit Tools/New-CrashTest.ps1): $summary.
// Der Fall wird isoliert mit dem vollständigen Server nachgestellt und darf
// nicht mehr abstürzen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  $fixture = class
  public
    [Test]
    procedure IsNotReproduced;
  end;

implementation

uses
  Shell.Replay,
  Shell.ReplayServer.Tests;

const
  cRequest =
    $(ConvertTo-DelphiLiteral $requestText '    ');

procedure $fixture.IsNotReproduced;
var
  mResult: TReplayResult;
begin
  mResult := TCrashReplayTest.Replay(cRequest, $filesExpr);
  Assert.IsTrue(mResult.Outcome = TReplayOutcome.NotReproduced, mResult.Text);
end;

initialization
  TDUnitX.RegisterTestFixture($fixture);

end.
"@
$source = ($source -replace "`r?`n", "`r`n")
New-Item -ItemType Directory -Force -Path $target | Out-Null
[IO.File]::WriteAllText($targetFile, $source, $Utf8Bom)

function Add-AfterLine([string] $File, [string] $Anchor, [string] $Line) {
    # BOM und CRLF der Datei bleiben, wie sie sind.
    $bytes = [IO.File]::ReadAllBytes($File)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($File)
    $index = $text.IndexOf($Anchor)
    if ($index -lt 0) { throw "Anker '$Anchor' fehlt in $File" }
    $end = $text.IndexOf("`n", $index)
    $text = $text.Substring(0, $end + 1) + $Line + "`r`n" + $text.Substring($end + 1)
    [IO.File]::WriteAllText($File, $text, [Text.UTF8Encoding]::new($bom))
}

$dpr = Join-Path $Root 'Tests/Atlas.Tests.dpr'
$dproj = Join-Path $Root 'Tests/Atlas.Tests.dproj'
Add-AfterLine $dpr '  Shell.ReplayServer.Tests in ' "  $unit in '$relativeDir\$unit.pas',"
Add-AfterLine $dproj 'Include="Application\Shell\Shell.ReplayServer.Tests.pas"' `
    "        <DCCReference Include=`"$relativeDir\$unit.pas`"/>"

Write-Host "Testunit angelegt: $targetFile"
Write-Host 'Eingetragen in Tests/Atlas.Tests.dpr und Tests/Atlas.Tests.dproj. Vor der Behebung schlägt der Test fehl.'
exit 0
