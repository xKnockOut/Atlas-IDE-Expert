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

    Geprüft werden alle Quelltexte unter Packages/Atlas.IDE.Expert/Source/.
    Kommentare werden übergangen.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-WindowHosts.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceDir = 'Packages/Atlas.IDE.Expert/Source'
$DockUnit = 'Atlas.IDE.Foundation.DockWindow.pas'
$BarUnit = 'Atlas.IDE.Foundation.EditorBarHost.pas'
$RefreshUnit = 'Atlas.IDE.Foundation.EditorRefresh.pas'

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

$violations = @()
$path = Join-Path $Root $SourceDir

foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas') {
    $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
    $text = Remove-PascalComments ([IO.File]::ReadAllText($file.FullName))

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

if ($violations.Count -gt 0) {
    Write-Host 'Fenster bzw. Leisten am gemeinsamen Host vorbei:' -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Atlas-Fenster laufen über TAtlasIdeDockWindow, Editorleisten über TAtlasEditorBarHost, Neuzeichnen über TAtlasIdeEditorRefresh.' -ForegroundColor Green
exit 0
