<#
.SYNOPSIS
    Prüft, dass Atlas-Fenster und Editorleisten über ihre gemeinsamen Hüllen laufen (#1248).

.DESCRIPTION
    Jede eigene Kopie der Fenster- bzw. Leistenverwaltung hatte früher
    dieselben Fehler (dunkles Thema fehlte, kein Abbau beim Entladen, Leiste
    nach dem Projektwechsel gesperrt). Deshalb gilt im IDE-Plugin:

    - Andockbare Fenster legt nur TAtlasIdeDockWindow an
      (Atlas.IDE.Foundation.DockWindow): CreateDockableForm und
      RegisterDockableForm stehen nur dort. Jede Unit mit einer Klasse, die
      INTACustomDockableForm umsetzt, erzeugt TAtlasIdeDockWindow.
    - Leisten im Editorfenster verwaltet TAtlasEditorBarHost
      (Atlas.IDE.Foundation.EditorBarHost): Nur dort wird das Editor-
      Steuerelement über FindComponent('Editor') gesucht; die Dienste nehmen
      EditorOf, TopEditor bzw. FocusEditor des Hosts.
    - Den Editor neu zeichnen lässt nur TAtlasIdeEditorRefresh
      (Atlas.IDE.Foundation.EditorRefresh): InvalidateTopEditor legt ohne
      offenes Editorfenster ein neues an, beim Beenden der IDE mit Absturz
      nach dem Entladen fremder Experten (#1233).
    - Im Code gebaute Dialoge erben von TAtlasDialog
      (Atlas.UI.Foundation.Dialog, #2062): kein eigenes inherited CreateNew,
      keine Schrift 'Segoe UI' von Hand (TAtlasUiTheme), kein clRed als
      Fehlerfarbe (TAtlasNoteLabel bzw. TAtlasUiTheme.TextColor). Die Stellen
      von vor #2064 stehen mit ihrer Anzahl je Datei in
      Tools/WindowHosts.baseline.json; mehr Treffer sind ein Verstoß, weniger
      verlangen das Senken der Baseline (-UpdateBaseline). Eine Zeile mit
      // window-ok ist ausgenommen (Überlagerungen und Popups ohne
      Dialogcharakter, mit Begründung im Kommentar).

    Geprüft werden alle Quelltexte unter Packages/Atlas.IDE.*/Source/.
    Kommentare werden übergangen.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-WindowHosts.ps1
.EXAMPLE
    pwsh Tools/Check-WindowHosts.ps1 -UpdateBaseline
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    # Zählt die Dialogregeln neu und schreibt Tools/WindowHosts.baseline.json (nur zum Senken verwenden).
    [switch] $UpdateBaseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Alle Plugin-Packages (Base und Module, #1456): Packages/Atlas.IDE.*/Source.
$SourceDirs = @(Get-ChildItem -Path (Join-Path $Root 'Packages') -Directory -Filter 'Atlas.IDE.*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'Source') } |
    ForEach-Object { "Packages/$($_.Name)/Source" })
$DockUnit = 'Atlas.IDE.Foundation.DockWindow.pas'
$BarUnit = 'Atlas.IDE.Foundation.EditorBarHost.pas'
$RefreshUnit = 'Atlas.IDE.Foundation.EditorRefresh.pas'
$DialogUnit = 'Atlas.UI.Foundation.Dialog.pas'
$ThemeUnit = 'Atlas.UI.Foundation.Theme.pas'
$BaselineFile = Join-Path $Root 'Tools/WindowHosts.baseline.json'

function Remove-PascalComments([string] $Text) {
    # Ersetzt Kommentare durch Leerzeichen, Strings bleiben (gesucht wird 'Editor'),
    # Zeilenumbrüche bleiben, damit Zeilennummern stimmen.
    $pattern = '(?s)''(?:[^'']|'''')*''|\{.*?\}|\(\*.*?\*\)|//[^\r\n]*'
    return [regex]::Replace($Text, $pattern, {
        param($m)
        if ($m.Value.StartsWith("'")) { return $m.Value }
        [regex]::Replace($m.Value, '[^\r\n]', ' ')
    })
}

function Get-LineNumber([string] $Text, [int] $Index) {
    return ($Text.Substring(0, $Index) -split "`n").Count
}

$Rules = @(
    @{ Pattern = '(?i)\b(Create|Register|Unregister)DockableForm\s*\('; Allowed = $DockUnit
       Message = 'Andockbares Fenster am Fenster-Host vorbei; TAtlasIdeDockWindow verwenden' },
    @{ Pattern = '(?i)\bFindComponent\s*\(\s*''Editor''\s*\)'; Allowed = $BarUnit
       Message = 'Editor-Steuerelement am Leisten-Host vorbei gesucht; TAtlasEditorBarHost.EditorOf/TopEditor/FocusEditor verwenden' },
    @{ Pattern = '(?i)\.\s*InvalidateTopEditor(LogicalLine)?\b'; Allowed = $RefreshUnit
       Message = 'Editor direkt neu gezeichnet (legt ohne Editorfenster eins an); TAtlasIdeEditorRefresh.InvalidateTop/InvalidateTopLine verwenden' }
)

# Dialogregeln (#2064): gezählt je Datei gegen Tools/WindowHosts.baseline.json.
$DialogRules = @(
    @{ Id = 'create-new'; Pattern = '(?i)\binherited\s+CreateNew\b'; Allowed = $DialogUnit
       Message = 'Dialog am Dialog-Host vorbei angelegt; von TAtlasDialog erben (CreateDialog)' },
    @{ Id = 'segoe-font'; Pattern = '(?i)\bFont\s*\.\s*Name\s*:=\s*''Segoe UI'''; Allowed = $ThemeUnit
       Message = 'Dialogschrift von Hand gesetzt; TAtlasUiTheme.AssignDialogFont bzw. TAtlasDialog verwenden' },
    @{ Id = 'cl-red'; Pattern = '(?i)\bclRed\b'; Allowed = ''
       Message = 'clRed als Fehlerfarbe; TAtlasNoteLabel.ShowNote bzw. TAtlasUiTheme.TextColor verwenden' }
)

function Get-ExemptLines([string] $RawText) {
    # Zeilennummern (ab 1) mit // window-ok.
    $mLines = $RawText -split "`n"
    $mResult = @{}
    for ($mIndex = 0; $mIndex -lt $mLines.Count; $mIndex++) {
        if ($mLines[$mIndex] -match '//\s*window-ok\b') { $mResult[$mIndex + 1] = $true }
    }
    return $mResult
}

$Baseline = @{}
if (Test-Path -LiteralPath $BaselineFile) {
    $Baseline = Get-Content -LiteralPath $BaselineFile -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
}
$Counts = [ordered]@{}

$violations = @()
$files = $SourceDirs | ForEach-Object { Get-ChildItem -Path (Join-Path $Root $_) -Recurse -File -Include '*.pas' }

foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($Root, $file.FullName) -replace '\\', '/'
    $raw = [IO.File]::ReadAllText($file.FullName)
    $text = Remove-PascalComments $raw
    $exempt = Get-ExemptLines $raw

    foreach ($rule in $DialogRules) {
        if ($file.Name -eq $rule.Allowed) { continue }
        $mFound = @([regex]::Matches($text, $rule.Pattern) | Where-Object { -not $exempt.Contains((Get-LineNumber $text $_.Index)) })
        if ($mFound.Count -eq 0) { continue }
        if (-not $Counts.Contains($relative)) { $Counts[$relative] = [ordered]@{} }
        $Counts[$relative][$rule.Id] = $mFound.Count
        $mAllowed = 0
        if ($Baseline.Contains($relative) -and $Baseline[$relative].Contains($rule.Id)) {
            $mAllowed = [int]$Baseline[$relative][$rule.Id]
        }
        if ($mFound.Count -gt $mAllowed) {
            foreach ($match in $mFound) {
                $violations += "${relative}:$(Get-LineNumber $text $match.Index): $($rule.Message)"
            }
        }
    }

    foreach ($rule in $Rules) {
        if ($file.Name -eq $rule.Allowed) { continue }
        foreach ($match in [regex]::Matches($text, $rule.Pattern)) {
            $violations += "${relative}:$(Get-LineNumber $text $match.Index): $($rule.Message)"
        }
    }

    if ($file.Name -ne $DockUnit) {
        $dock = [regex]::Match($text, '(?i)class\s*\(\s*TInterfacedObject\s*,\s*INTACustomDockableForm\b')
        if ($dock.Success -and $text -notmatch '(?i)\bTAtlasIdeDockWindow\s*\.\s*Create\b') {
            $violations += "${relative}:$(Get-LineNumber $text $dock.Index): INTACustomDockableForm ohne TAtlasIdeDockWindow"
        }
    }
}

if ($UpdateBaseline) {
    $mJson = ($Counts | ConvertTo-Json -Depth 4) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($BaselineFile, $mJson + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Baseline geschrieben: $($Counts.Count) Dateien." -ForegroundColor Green
    exit 0
}

# Weniger Treffer als in der Baseline: senken, damit nichts Neues unbemerkt nachrückt.
foreach ($mFile in $Baseline.Keys) {
    foreach ($mRule in $Baseline[$mFile].Keys) {
        $mNow = 0
        if ($Counts.Contains($mFile) -and $Counts[$mFile].Contains($mRule)) { $mNow = [int]$Counts[$mFile][$mRule] }
        if ($mNow -lt [int]$Baseline[$mFile][$mRule]) {
            $violations += "${mFile}: ${mRule} nur noch $mNow statt $($Baseline[$mFile][$mRule]); Baseline senken (pwsh Tools/Check-WindowHosts.ps1 -UpdateBaseline)"
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'Fenster bzw. Leisten am gemeinsamen Host vorbei:' -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Atlas-Fenster laufen über TAtlasIdeDockWindow, Editorleisten über TAtlasEditorBarHost, Neuzeichnen über TAtlasIdeEditorRefresh, Dialoge über TAtlasDialog (Baseline eingehalten).' -ForegroundColor Green
exit 0
