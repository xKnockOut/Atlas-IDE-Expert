<#
.SYNOPSIS
    Prüft, dass Atlas-Fenster und Editorleisten über ihre gemeinsamen Hüllen laufen (#1248).

.DESCRIPTION
    Jede eigene Kopie der Fenster- bzw. Leistenverwaltung hatte früher
    dieselben Fehler (dunkles Thema fehlte, kein Abbau beim Entladen, Leiste
    nach dem Projektwechsel gesperrt). Deshalb gilt im IDE-Plugin:

    - Andockbare Fenster legt nur TAtlasIdeDockWindow an
      (Atlas.ToolsApi.Windows.DockWindow): CreateDockableForm und
      RegisterDockableForm stehen nur dort. Jede Unit mit einer Klasse, die
      INTACustomDockableForm umsetzt, erzeugt TAtlasIdeDockWindow.
    - Leisten im Editorfenster verwaltet TAtlasEditorBarHost
      (Atlas.ToolsApi.EditorBars.Host): Nur dort wird das Editor-
      Steuerelement über FindComponent('Editor') gesucht; die Dienste nehmen
      EditorOf, TopEditor bzw. FocusEditor des Hosts.
    - Den Editor neu zeichnen lässt nur TAtlasIdeEditorRefresh
      (Atlas.ToolsApi.Editor.Refresh): InvalidateTopEditor legt ohne
      offenes Editorfenster ein neues an, beim Beenden der IDE mit Absturz
      nach dem Entladen fremder Experten (#1233).
    - Zeigen, Verstecken und Sichtbarkeit eines Dockfensters laufen über
      TAtlasIdeDockWindow.Present, HideIfAny und IsShown: keine eigene
      nil-Prüfung vor Host.Hide bzw. Host.Shown und kein zweites UpdateIcon
      nach Show (jedes neue Fenster brachte sonst dieselben Zeilen mit).
    - Im Code gebaute Dialoge erben von TAtlasDialog
      (Atlas.Vcl.Forms.Dialog, #2062): kein eigenes inherited CreateNew,
      keine Schrift 'Segoe UI' von Hand (TAtlasUiTheme), kein clRed als
      Fehlerfarbe (TAtlasNoteLabel bzw. TAtlasUiTheme.TextColor). Auch kein
      Formular, das von außen über X.CreateNew angelegt wird (TForm.CreateNew(nil)
      bekommt weder Dialogschrift noch IDE-Thema), und keine Fensterklasse
      direkt von TForm (create-new-call, form-class).
    - Rahmenlose Fenster erben von TAtlasPopupForm (CreatePopup), nicht von
      TAtlasDialog mit BorderStyle := bsNone: Die Dialogbasis legt ein
      Dialogfenster an, das bsNone wieder verwirft, und Schatten, runde Ecken
      und Akzentrand müsste jedes Fenster selbst nachtragen.
    - Umbrechende Beschriftungen sind TAtlasWrapLabel
      (Atlas.Vcl.Controls.WrapLabel): Ein TLabel mit WordWrap rechnet seine
      Höhe bei der Anfangsbreite (65 Pixel) und behält sie, wenn Align oder
      Anker es danach breiter machen; über der Liste blieb so ein großer
      leerer Bereich (wrap-label, jedes „.WordWrap := True“). Memos und
      TAtlasNoteLabel brechen ohnehin um. Die Altstellen (Dialoge
      von vor #2064, Fenster ohne TAtlasDialog) stehen mit ihrer Anzahl je Datei in
      Tools/WindowHosts.baseline.json; mehr Treffer sind ein Verstoß, weniger
      verlangen das Senken der Baseline (-UpdateBaseline). Eine Zeile mit
      // window-ok ist ausgenommen (Überlagerungen und Popups ohne
      Dialogcharakter, mit Begründung im Kommentar).
    - Listen sind TAtlasListBox (Atlas.Vcl.Controls.ListBox): Unter dem
      Stil der IDE zeichnet eine TListBox beim Wechsel des Fokus die ganze
      Fläche in der Grundfarbe vor den Zeilen, die Liste blitzt leer auf
      (TListBox.Create steht nur dort).
    - Ein Teiler (TSplitter) bekommt vor dem Ausrichten seine Lage (Top bei
      alTop/alBottom, Left bei alLeft/alRight) neben dem Steuerelement, das er
      verstellt (splitter-position). Die VCL ordnet gleich ausgerichtete
      Steuerelemente nach ihrer Lage; ohne Lage landete der Teiler im Fenster
      „Atlas-Tests“ über dem Tastenhinweis statt über den Einzelheiten und zog
      dessen Höhe: großer leerer Bereich, der Baum schrumpfte. Geprüft wird,
      dass die Unit Top oder Left des Teilers setzt.
    - Systemfarben (clGrayText, clHighlight, clWindowText …) nur über den
      Stil (system-color): TAtlasUiTheme.SystemColor zum Zeichnen,
      TAtlasUiTheme.UseFontColor für die Schrift eines Steuerelements,
      sonst StyleServices(…).GetSystemColor. Direkt in Canvas.Font.Color
      oder Brush.Color nimmt eine Systemfarbe die Farbe von Windows, im
      dunklen IDE-Thema also eine helle; in Font.Color eines Steuerelements
      mit seFont übergeht der Stil sie ganz (ein grauer Hinweis wird zur
      normalen Schrift). Ausgenommen sind die Unit des Themendienstes und
      Zeilen mit // window-ok und Begründung (Werte, die der Stil danach
      abbildet, Farben ohne IDE-Thema, Farbwerte für entworfene Formulare).
      Zeichenketten zählen nicht (Namen der Farben im Visualisierer).
    - Selbst gefärbte Zeilen von Listen und Bäumen fragen nicht cdsSelected
      ab (cds-selected): Die IDE meldet es bei jeder Zeile; wer dann nur die
      Auswahlschrift setzt, zeichnet hell auf der weißen Fläche von Windows.
      Gewählt ist, was Item.Selected bzw. Node.Selected sagt;
      TAtlasUiTheme.RowColors färbt die Zeile.
    - Eine Liste wird nur in einer Methode CreateWnd virtuell
      (Style := lbVirtual bzw. lbVirtualOwnerDraw; virtual-listbox-style):
      SetStyle leert die Einträge per LB_RESETCONTENT und legt dafür das
      Fenster der Liste an. Im Konstruktor fehlt der Parent bzw. dessen
      Fenster (die IDE hängt den Frame eines Dockfensters erst nach dem
      Anlegen ein): „Element … hat kein übergeordnetes Fenster“, und die
      Sicherung schaltet die Funktion ab. In CreateWnd des Frames bzw. des
      Parents ist dessen Fenster da.
    - Der Frame eines andockbaren Fensters (Ergebnis von GetFrameClass) hat
      eine DFM: {$R *.dfm} in seiner Unit und die .dfm daneben. Die IDE legt
      ihn über TCustomFrame.Create an, das ohne Ressource EResNotFound
      auslöst; das Fenster öffnet dann nicht (#609, #612).

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

# Alle Plugin-Packages (Base und Module, #1456): Packages/Atlas.IDE.*/Source, dazu die Platform-Packages des
# Plugins, die Base als Quelltext mitübersetzt (Atlas.Plugin, Atlas.Vcl, Atlas.ToolsApi).
$SourceDirs = @(Get-ChildItem -Path (Join-Path $Root 'Packages') -Directory |
    Where-Object { $_.Name -like 'Atlas.IDE.*' -or $_.Name -in @('Atlas.Plugin', 'Atlas.Vcl', 'Atlas.ToolsApi') } |
    Where-Object { Test-Path (Join-Path $_.FullName 'Source') } |
    ForEach-Object { "Packages/$($_.Name)/Source" })
$DockUnit = 'Atlas.ToolsApi.Windows.DockWindow.pas'
$BarUnit = 'Atlas.ToolsApi.Editor.Windows.pas'
$RefreshUnit = 'Atlas.ToolsApi.Editor.Refresh.pas'
$DialogUnit = 'Atlas.Vcl.Forms.Dialog.pas'
$ThemeUnit = 'Atlas.Vcl.Theme.Service.pas'
$WrapLabelUnit = 'Atlas.Vcl.Controls.WrapLabel.pas'
$ListBoxUnit = 'Atlas.Vcl.Controls.ListBox.pas'
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

function Remove-PascalStrings([string] $Text) {
    # Inhalt von Zeichenketten durch Leerzeichen ersetzen (nach Remove-PascalComments): Namen von Farben in Texten
    # sind keine Farben.
    return [regex]::Replace($Text, '''(?:[^''\r\n]|'''')*''', {
        param($m)
        "'" + (' ' * ($m.Value.Length - 2)) + "'"
    })
}

# Systemfarben der VCL (clScrollBar bis clMenuBar).
$SystemColorPattern = '(?i)\bcl(ScrollBar|Background|ActiveCaption|InactiveCaption|Menu|Window|WindowFrame|MenuText|' +
    'WindowText|CaptionText|ActiveBorder|InactiveBorder|AppWorkSpace|Highlight|HighlightText|BtnFace|BtnShadow|' +
    'GrayText|BtnText|InactiveCaptionText|BtnHighlight|3DDkShadow|3DLight|InfoText|InfoBk|HotLight|' +
    'GradientActiveCaption|GradientInactiveCaption|MenuHighlight|MenuBar)\b'

function Test-StyledColor([string] $Text, [int] $Index) {
    # Wahr, wenn die Farbe an $Index ein Argument von GetSystemColor, TAtlasUiTheme.SystemColor oder
    # TAtlasUiTheme.UseFontColor ist: innerste offene Klammer davor suchen, dann den Namen davor.
    $mDepth = 0
    for ($mPos = $Index - 1; $mPos -ge 0; $mPos--) {
        $mChar = $Text[$mPos]
        if ($mChar -eq ')') { $mDepth++ }
        elseif ($mChar -eq ';') { return $false }
        elseif ($mChar -eq '(') {
            if ($mDepth -eq 0) {
                $mStart = [Math]::Max(0, $mPos - 40)
                return $Text.Substring($mStart, $mPos - $mStart + 1) -match '(?i)\b(GetSystemColor|SystemColor|UseFontColor)\s*\($'
            }
            $mDepth--
        }
    }
    return $false
}

function Get-LineNumber([string] $Text, [int] $Index) {
    return ($Text.Substring(0, $Index) -split "`n").Count
}

$Rules = @(
    @{ Pattern = '(?i)\b(Create|Register|Unregister)DockableForm\s*\('; Allowed = $DockUnit
       Message = 'Andockbares Fenster am Fenster-Host vorbei; TAtlasIdeDockWindow verwenden' },
    @{ Pattern = '(?i)\bFindComponent\s*\(\s*''Editor''\s*\)'; Allowed = $BarUnit
       Message = 'Editor-Steuerelement an TAtlasIdeEditorWindows vorbei gesucht; TAtlasIdeEditorWindows.EditorOf/TopEditor/FocusEditor verwenden' },
    @{ Pattern = '(?i)\.\s*InvalidateTopEditor(LogicalLine)?\b'; Allowed = $RefreshUnit
       Message = 'Editor direkt neu gezeichnet (legt ohne Editorfenster eins an); TAtlasIdeEditorRefresh.InvalidateTop/InvalidateTopLine verwenden' },
    @{ Pattern = '(?i)\bif\s+(F?Host)\s*<>\s*nil\s+then\s+begin\s+\1\s*\.\s*Hide\s*;\s*end\b'; Allowed = $DockUnit
       Message = 'Dockfenster mit eigener nil-Prüfung versteckt; TAtlasIdeDockWindow.HideIfAny verwenden' },
    @{ Pattern = '(?i)\(\s*(F?Host)\s*<>\s*nil\s*\)\s*and\s*\1\s*\.\s*Shown\b'; Allowed = $DockUnit
       Message = 'Sichtbarkeit des Dockfensters mit eigener nil-Prüfung; TAtlasIdeDockWindow.IsShown verwenden' },
    @{ Pattern = '(?is)\.\s*Show\s*\(\s*(\w+)\s*\)\s*;\s*if\s+\1\s+then\s+begin\s+TAtlasIdeDockWindow\s*\.\s*UpdateIcon\s*\(\s*\w+\s*\)\s*;\s*end\b'; Allowed = $DockUnit
       Message = 'Symbol nach Show(…) noch einmal gesetzt (Show setzt es beim Anlegen selbst); TAtlasIdeDockWindow.Present verwenden' },
    @{ Pattern = '(?i)\bTListBox\s*\.\s*Create\b'; Allowed = $ListBoxUnit
       Message = 'TListBox flackert unter dem Stil der IDE (leere Fläche vor den Zeilen); TAtlasListBox verwenden' },
    @{ Pattern = '(?i)\bcdsSelected\b'; Allowed = ''
       Message = 'cdsSelected ist in der IDE bei jeder Zeile gesetzt (helle Auswahlschrift auf weißer Fläche); Item.Selected bzw. Node.Selected und TAtlasUiTheme.RowColors verwenden' }
)

# Dialogregeln (#2064): gezählt je Datei gegen Tools/WindowHosts.baseline.json.
$DialogRules = @(
    @{ Id = 'create-new'; Pattern = '(?i)\binherited\s+CreateNew\b'; Allowed = $DialogUnit
       Message = 'Dialog am Dialog-Host vorbei angelegt; von TAtlasDialog erben (CreateDialog)' },
    @{ Id = 'segoe-font'; Pattern = '(?i)\bFont\s*\.\s*Name\s*:=\s*''Segoe UI'''; Allowed = $ThemeUnit
       Message = 'Dialogschrift von Hand gesetzt; TAtlasUiTheme.AssignDialogFont bzw. TAtlasDialog verwenden' },
    @{ Id = 'cl-red'; Pattern = '(?i)\bclRed\b'; Allowed = ''
       Message = 'clRed als Fehlerfarbe; TAtlasNoteLabel.ShowNote bzw. TAtlasUiTheme.TextColor verwenden' },
    @{ Id = 'create-new-call'; Pattern = '(?i)(?<!\binherited\s+)\b\w+\s*\.\s*CreateNew\s*\('; Allowed = $DialogUnit
       Message = 'Formular von außen über CreateNew angelegt (ohne Dialogschrift und IDE-Thema); TAtlasDialog.CreateDialog bzw. eine Unterklasse von TAtlasDialog verwenden' },
    @{ Id = 'form-class'; Pattern = '(?i)=\s*class\s*\(\s*TForm\s*\)'; Allowed = $DialogUnit
       Message = 'Fensterklasse direkt von TForm (ohne Dialogschrift und IDE-Thema); von TAtlasDialog erben' },
    @{ Id = 'wrap-label'; Pattern = '(?i)\.\s*WordWrap\s*:=\s*True\b'; Allowed = $WrapLabelUnit
       Message = 'WordWrap von Hand: TLabel rechnet die Höhe bei der Anfangsbreite und behält sie, wenn Align oder Anker die Breite ändern; TAtlasWrapLabel verwenden (Memos brechen ohnehin um)' }
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
# Frame-Klasse aus GetFrameClass → Fundstelle (für die DFM-Prüfung nach der Schleife).
$FrameClasses = [ordered]@{}
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

    # Systemfarben am Stil vorbei (system-color).
    if ($file.Name -ne $ThemeUnit) {
        $mColors = Remove-PascalStrings $text
        foreach ($match in [regex]::Matches($mColors, $SystemColorPattern)) {
            $mLine = Get-LineNumber $mColors $match.Index
            if ($exempt.Contains($mLine) -or (Test-StyledColor $mColors $match.Index)) { continue }
            $violations += "${relative}:${mLine}: Systemfarbe $($match.Value) am Stil vorbei (im dunklen IDE-Thema hell bzw. ohne Wirkung); TAtlasUiTheme.SystemColor zum Zeichnen, TAtlasUiTheme.UseFontColor für die Schrift"
        }
    }

    # Teiler ohne Lage: Die VCL ordnet gleich ausgerichtete Steuerelemente nach Top bzw. Left (splitter-position).
    foreach ($match in [regex]::Matches($text, '(?i)\b([\w.]+)\s*:=\s*TSplitter\s*\.\s*Create\b')) {
        $mLine = Get-LineNumber $text $match.Index
        if ($exempt.Contains($mLine)) { continue }
        $mName = [regex]::Escape($match.Groups[1].Value) -replace '\\\.', '\s*\.\s*'
        if ($text -notmatch ('(?i)(?<![\w.])' + $mName + '\s*\.\s*(Top|Left)\s*:=')) {
            $violations += "${relative}:${mLine}: Teiler ohne Top bzw. Left; vor Align und Parent neben das Steuerelement setzen, das er verstellt (die VCL ordnet gleich ausgerichtete Steuerelemente nach ihrer Lage, sonst zieht der Teiler den falschen Nachbarn)"
        }
    }

    # Virtuelle Liste nur in CreateWnd: SetStyle braucht das Fenster des Parents (virtual-listbox-style).
    foreach ($match in [regex]::Matches($text, '(?i)\bStyle\s*:=\s*lbVirtual(OwnerDraw)?\b')) {
        $mLine = Get-LineNumber $text $match.Index
        if ($exempt.Contains($mLine)) { continue }
        $mHeads = [regex]::Matches($text.Substring(0, $match.Index), '(?im)^\s*(class\s+)?(procedure|function|constructor|destructor)\s+([\w.]+)')
        $mRoutine = ''
        if ($mHeads.Count -gt 0) { $mRoutine = $mHeads[$mHeads.Count - 1].Groups[3].Value }
        if ($mRoutine -notmatch '(?i)(^|\.)CreateWnd$') {
            $violations += "${relative}:${mLine}: Liste außerhalb von CreateWnd virtuell geschaltet ($mRoutine); SetStyle leert per LB_RESETCONTENT und braucht das Fenster des Parents (im Konstruktor: kein übergeordnetes Fenster). In CreateWnd des Parents setzen"
        }
    }

    # Rahmenlose Fenster gehören auf TAtlasPopupForm: Ein Nachfahre von TAtlasDialog (auch über TAtlasAnswerDialog),
    # der den Rahmen abschaltet. Die Unit der Basisklassen selbst schaltet ihn nur in TAtlasPopupForm.CreatePopup ab.
    $declaresPopupForm = $text -match '(?i)\bTAtlasPopupForm\s*=\s*class\s*\(\s*TForm\s*\)'
    if (-not $declaresPopupForm -and $text -match '(?i)=\s*class\s*\(\s*TAtlas(Answer)?Dialog\s*\)') {
        foreach ($match in [regex]::Matches($text, '(?im)^\s*(Self\s*\.\s*)?BorderStyle\s*:=\s*bsNone\b')) {
            $violations += "${relative}:$(Get-LineNumber $text $match.Index): Rahmenloses Fenster auf TAtlasDialog; von TAtlasPopupForm erben (CreatePopup)"
        }
    }

    if ($file.Name -ne $DockUnit) {
        $dock = [regex]::Match($text, '(?i)class\s*\(\s*TInterfacedObject\s*,\s*INTACustomDockableForm\b')
        if ($dock.Success -and $text -notmatch '(?i)\bTAtlasIdeDockWindow\s*\.\s*Create\b') {
            $violations += "${relative}:$(Get-LineNumber $text $dock.Index): INTACustomDockableForm ohne TAtlasIdeDockWindow"
        }
    }

    $mFramePattern = '(?is)\.\s*GetFrameClass\s*:\s*TCustomFrameClass\s*;\s*begin\s*Result\s*:=\s*(\w+)\s*;'
    foreach ($match in [regex]::Matches($text, $mFramePattern)) {
        $FrameClasses[$match.Groups[1].Value] = "${relative}:$(Get-LineNumber $text $match.Index)"
    }
}

# Frames der Dockfenster brauchen eine DFM-Ressource (TCustomFrame.Create, sonst EResNotFound). Es genügt die eines
# Atlas-Vorfahren (InitInheritedComponent liest die Kette): Die Tafel der Startseite erbt die von TAtlasWelcomeFrame.
$Declarations = @{}
foreach ($file in $files) {
    $mPlain = Remove-PascalComments ([IO.File]::ReadAllText($file.FullName))
    foreach ($match in [regex]::Matches($mPlain, '(?i)\b(T\w+)\s*=\s*class\s*\(\s*(\w+)')) {
        $Declarations[$match.Groups[1].Value] = @{ File = $file; Parent = $match.Groups[2].Value }
    }
}

function Test-FrameResource([string] $Class) {
    # Wahr, wenn die Unit von $Class {$R *.dfm} hat und die .dfm daneben ein Objekt dieser Klasse beschreibt.
    $mDeclaration = $Declarations[$Class]
    $mDfm = [IO.Path]::ChangeExtension($mDeclaration.File.FullName, '.dfm')
    if ([IO.File]::ReadAllText($mDeclaration.File.FullName) -notmatch '(?i)\{\$R\s+\*\.dfm\}') { return $false }
    if (-not (Test-Path -LiteralPath $mDfm)) { return $false }
    return [IO.File]::ReadAllText($mDfm) -match ('(?im)^\W*(object|inherited|inline)\s+\w+\s*:\s*' + [regex]::Escape($Class) + '\b')
}

foreach ($mClass in $FrameClasses.Keys) {
    if (-not $Declarations.ContainsKey($mClass)) {
        $violations += "$($FrameClasses[$mClass]): Frame-Klasse $mClass nicht gefunden"
        continue
    }
    $mCurrent = $mClass
    $mFound = $false
    while ($Declarations.ContainsKey($mCurrent)) {
        if (Test-FrameResource $mCurrent) {
            $mFound = $true
            break
        }
        $mCurrent = $Declarations[$mCurrent].Parent
    }
    if (-not $mFound) {
        $mRelative = [IO.Path]::GetRelativePath($Root, $Declarations[$mClass].File.FullName) -replace '\\', '/'
        $violations += "${mRelative}: Frame $mClass eines Dockfensters ohne DFM ({`$R *.dfm} und .dfm, auch kein Vorfahr); die IDE kann ihn nicht anlegen (EResNotFound)"
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

Write-Host 'Atlas-Fenster laufen über TAtlasIdeDockWindow, Editorleisten über TAtlasEditorBarHost, Neuzeichnen über TAtlasIdeEditorRefresh, Dialoge über TAtlasDialog (Baseline eingehalten), Systemfarben über den Stil, Frames der Dockfenster mit DFM.' -ForegroundColor Green
exit 0
