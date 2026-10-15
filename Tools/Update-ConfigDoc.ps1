<#
.SYNOPSIS
    Erzeugt aus dem JSON-Schema von atlas.json die Doku, die Einstellungstabelle
    und die Schema-Unit des Plugins und prüft den Parser dagegen.

.DESCRIPTION
    Einzige Quelle ist schemas/atlas.schema.json (#265):
    - docs/Konfiguration.md: jeder Schlüssel mit Typ, Standardwert, erlaubten
      Werten und Beschreibung; verschachtelte Objekte als eigener Abschnitt.
    - docs/Einstellungen.md: Tabelle für das Einstellungs-Plugin (#227) aus den
      Angaben x-page, x-control, x-issue, x-commandLine und x-restart.
      x-quickToggle (mit x-plugin, x-caption, x-captionEn) an einer booleschen
      Einstellung macht sie zum Schnellschalter im Plugin (#604).
    - Wächter: Die Schlüssel in Atlas.Common.Configuration.Parser müssen genau
      denen im Schema entsprechen (Validierung und Schichtung).
    - Atlas.Common.Configuration.Internals.ScopeData: Ort jedes Schlüssels aus
      x-scope ("global" = %APPDATA%\Atlas\settings.json, "project" = atlas.json).
      Jeder Schlüssel der obersten Ebene braucht x-scope; ein Glied darf mit
      eigenem x-scope abweichen (gemischtes Objekt wie index, completion).

    Mit -Check wird nichts geschrieben; Exit-Code 1, wenn eine Datei veraltet ist
    oder der Parser abweicht.

    Pflegeregel: Neue Einstellung -> Schema (mit x-page, x-control, x-issue),
    Parser, Test; dann dieses Skript ausführen.

.EXAMPLE
    pwsh Tools/Update-ConfigDoc.ps1
    pwsh Tools/Update-ConfigDoc.ps1 -Check
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SchemaPath = Join-Path $Root 'schemas/atlas.schema.json'
$DocPath = Join-Path $Root 'docs/Konfiguration.md'
$TablePath = Join-Path $Root 'docs/Einstellungen.md'
$ParserPath = Join-Path $Root 'Packages/Atlas.Common/Source/Configuration/Atlas.Common.Configuration.Parser.pas'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$Schema = Get-Content -Raw -Encoding utf8 $SchemaPath | ConvertFrom-Json -AsHashtable

function Has([hashtable] $Node, [string] $Key) { $Node.ContainsKey($Key) -and $null -ne $Node[$Key] }

function Format-Value($Value) {
    if ($Value -is [bool]) { return '`' + $Value.ToString().ToLowerInvariant() + '`' }
    if ($Value -is [string]) { return '`"' + $Value + '"`' }
    return '`' + ($Value | ConvertTo-Json -Compress) + '`'
}

function Escape([string] $Text) { $Text.Replace('|', '\|').Replace("`r", '').Replace("`n", ' ') }

# Ort eines Schlüssels: eigenes x-scope, sonst das des Objekts.
function Scope-Of([hashtable] $Node, [string] $Inherited) { if (Has $Node 'x-scope') { $Node['x-scope'] } else { $Inherited } }

function Scope-Text([string] $Scope) {
    if ($Scope -eq 'global') { return 'global (settings.json)' }
    if ($Scope -eq 'project') { return 'Projekt (atlas.json)' }
    return ''
}

function Write-Table([System.Text.StringBuilder] $Out, [hashtable] $Properties, [string] $Prefix, [string] $ParentScope) {
    [void]$Out.AppendLine('| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |')
    [void]$Out.AppendLine('|---|---|---|---|---|---|')
    foreach ($Name in $Properties.Keys) {
        if ($Name -eq '$schema') { continue }
        $P = $Properties[$Name]
        $Type = if (Has $P 'type') { $P['type'] } else { '' }
        if ($Type -eq 'array' -and (Has $P 'items') -and (Has $P['items'] 'type')) { $Type = "array<$($P['items']['type'])>" }
        $Default = if ($P.ContainsKey('default')) { Format-Value $P['default'] } else { '–' }
        $Values = if (Has $P 'enum') { ($P['enum'] | ForEach-Object { Format-Value $_ }) -join ', ' }
                  elseif (Has $P 'examples') { 'z. B. ' + (($P['examples'] | ForEach-Object { Format-Value $_ }) -join ', ') }
                  elseif ((Has $P 'minimum') -or (Has $P 'maximum')) { "$(if (Has $P 'minimum') { $P['minimum'] } else { '' })…$(if (Has $P 'maximum') { $P['maximum'] } else { '' })" }
                  else { '' }
        $Description = if (Has $P 'description') { Escape $P['description'] } else { '' }
        $Place = Scope-Text (Scope-Of $P $ParentScope)
        if (Has $P 'properties') {
            $Inner = @($P['properties'].Values | ForEach-Object { Scope-Of $_ (Scope-Of $P $ParentScope) } | Sort-Object -Unique)
            if ($Inner.Count -gt 1) { $Place = 'gemischt, siehe unten' }
        }
        [void]$Out.AppendLine("| ``$Prefix$Name`` | $Place | $Type | $Default | $Values | $Description |")
    }
}

$Out = New-Object System.Text.StringBuilder
[void]$Out.AppendLine('# Konfiguration: atlas.json')
[void]$Out.AppendLine()
[void]$Out.AppendLine('<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->')
[void]$Out.AppendLine()
[void]$Out.AppendLine((Escape $Schema['description']))
[void]$Out.AppendLine()
[void]$Out.AppendLine('Jeder Schlüssel hat genau einen Ort (Spalte „Ort“): Projekt-Schlüssel stehen in `atlas.json` im Projektordner (im Plugin *Atlas › Projekt-Einstellungen*), globale in `%APPDATA%\Atlas\settings.json` für alle Projekte (im Plugin *Tools › Optionen › Atlas*). Ein Schlüssel am falschen Ort wird ignoriert und als Warnung gemeldet. Fehlende Schlüssel nehmen den Standardwert. In der IDE bestimmt die laufende IDE die Delphi-Version (`delphiVersion` gilt dort nicht). Die Prüfregeln stehen in [Regeln.md](Regeln.md).')
[void]$Out.AppendLine()
[void]$Out.AppendLine('## Schlüssel')
[void]$Out.AppendLine()
Write-Table $Out $Schema['properties'] '' ''
foreach ($Name in $Schema['properties'].Keys) {
    $P = $Schema['properties'][$Name]
    if ((Has $P 'properties')) {
        [void]$Out.AppendLine()
        [void]$Out.AppendLine("## $Name")
        [void]$Out.AppendLine()
        Write-Table $Out $P['properties'] "$Name." (Scope-Of $P '')
    }
}
[void]$Out.AppendLine()
[void]$Out.AppendLine('## Beispiel')
[void]$Out.AppendLine()
[void]$Out.AppendLine('```json')
[void]$Out.AppendLine('{')
[void]$Out.AppendLine('  "$schema": "https://raw.githubusercontent.com/xKnockOut/Atlas/main/schemas/atlas.schema.json",')
[void]$Out.AppendLine('  "project": "App.dproj",')
[void]$Out.AppendLine('  "config": "Debug",')
[void]$Out.AppendLine('  "platform": "Win64",')
[void]$Out.AppendLine('  "rules": { "empty-except": "error" },')
[void]$Out.AppendLine('  "exclude": ["ThirdParty/**"]')
[void]$Out.AppendLine('}')
[void]$Out.AppendLine('```')
$Text = $Out.ToString().Replace("`r`n", "`n")

# --- Einstellungstabelle für das Plugin (#227) ---
$Table = New-Object System.Text.StringBuilder
[void]$Table.AppendLine('# Einstellungen')
[void]$Table.AppendLine()
[void]$Table.AppendLine('<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->')
[void]$Table.AppendLine()
[void]$Table.AppendLine('Alle Einstellungen mit Seite und Bedienelement im Einstellungs-Plugin (#227). Einzelheiten zu Werten und Bedeutung stehen in [Konfiguration.md](Konfiguration.md).')
[void]$Table.AppendLine()
[void]$Table.AppendLine('| Seite | Einstellung | Standard | Quelle | Neustart | Bedienelement | Herkunft |')
[void]$Table.AppendLine('|---|---|---|---|---|---|---|')
foreach ($Name in $Schema['properties'].Keys) {
    if ($Name -eq '$schema') { continue }
    $P = $Schema['properties'][$Name]
    $Setting = '`' + $Name + '`'
    if (Has $P 'properties') { $Setting += ': ' + (($P['properties'].Keys | ForEach-Object { '`' + $_ + '`' }) -join ', ') }
    $Default = if ($P.ContainsKey('default')) { Format-Value $P['default'] } else { '–' }
    $Scope = Scope-Of $P ''
    $Source = if ($Scope -eq 'global') { 'settings.json (Tools › Optionen › Atlas)' } else { 'atlas.json (Atlas › Projekt-Einstellungen)' }
    if (Has $P 'properties') {
        $Other = @($P['properties'].Keys | Where-Object { (Scope-Of $P['properties'][$_] $Scope) -ne $Scope })
        if ($Other.Count -gt 0) {
            $OtherFile = if ($Scope -eq 'global') { 'atlas.json' } else { 'settings.json' }
            $Source += '; ' + (($Other | ForEach-Object { '`' + $_ + '`' }) -join ', ') + " in $OtherFile"
        }
    }
    if (Has $P 'x-commandLine') { $Source += ', ``' + $P['x-commandLine'] + '``' }
    $Restart = if ((Has $P 'x-restart') -and $P['x-restart']) { 'ja' } else { 'nein' }
    $Page = if (Has $P 'x-page') { $P['x-page'] } else { '' }
    $Control = if (Has $P 'x-control') { $P['x-control'] } else { '' }
    $Issue = if (Has $P 'x-issue') { $P['x-issue'] } else { '' }
    [void]$Table.AppendLine("| $Page | $Setting | $Default | $Source | $Restart | $(Escape $Control) | $Issue |")
}
# Was kein Schlüssel in atlas.json ist, aber im Plugin erscheint.
[void]$Table.AppendLine('| Allgemein | Pfad zu `AtlasServer.exe` | – | Plugin (Registry `ServerPath`) | ja | Datei wählen, Version anzeigen | #12 |')
[void]$Table.AppendLine('| Baseline | `atlas-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |')
[void]$Table.AppendLine('| Baseline | Unterdrückungen `lsp-ignore` | – | `--suppression-stats` | nein | Übersicht je Regel (nur Anzeige) | #147 |')
[void]$Table.AppendLine('| Speicher | Index-Cache löschen | – | `--clear-cache`, Befehl `atlas.server.clearIndex` (löschen und neu indizieren), `atlas.server.rebuildIndex` (nur neu indizieren) | nein | Knöpfe „Index löschen“ und „Index neu aufbauen“ | #184, #492 |')
[void]$Table.AppendLine('| Allgemein | Atlas-Feld in der Statusleiste (`statusField.enabled`), Kurztext (`statusField.showSummary`), Schnellschalter öffnen mit (`statusField.openToggles`: both, rightClick, doubleClick), ausgeblendete Zeilen (`statusField.hidden`) | an, an, both, – | Plugin (Registry `StatusField`, `StatusFieldSummary`, `StatusFieldToggles`, `StatusFieldHidden`) | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Textfeld mit Kennungen | #591 |')
[void]$Table.AppendLine('| Allgemein | Fortschritt beim Aufbau des Symbol-Index (`statusField.indexProgress`: statusField, menu, off); mit abgeschaltetem Statusfeld steht er im Menütitel | statusField | Plugin (Registry `IndexProgressPlace`) | nein | Auswahl | #492, #591 |')
[void]$Table.AppendLine('| Allgemein | Schnellschalter (#604): Fenster über dem Statusfeld (Rechtsklick oder Doppelklick) und Tastenkürzel; Schalter = jede boolesche Einstellung mit `x-quickToggle` (Plugin-Katalog und `atlas.schema.json`) | Strg+Umschalt+Alt+A | Plugin (Registry `QuickToggleKey`, `QuickToggleKeyPriority`) | nein | Taste auf der Seite „Tastenkonflikte“; „Alles aus für diese Sitzung“ ändert keine Einstellung | #604 |')
[void]$Table.AppendLine('| Allgemein | Diagnosemodus (`diagnosticMode.enabled`, Schnellschalter): andockbares Fenster „Atlas-Diagnose“ mit der Dauer jedes Schritts der letzten Abfrage (Kontext, je Quelle mit Namen, Filtern und Sortieren, Zeichnen, bis zur Liste, Anzahl der Einträge) sowie Mittelwert und Maximum der letzten 50 Abfragen; Überschreitungen des Budgets aus #409 in Warnfarbe; „Bericht kopieren“ ohne Quelltext, Dateinamen nur mit Häkchen; gelbe Zeile im Statusfeld; Tastenkürzel (Strg+Alt+Umschalt+A gehört den Schnellschaltern) | aus, Strg+Umschalt+Alt+D | Plugin (Registry `DiagnosticMode`, `DiagnosticModeKey`, `DiagnosticModeKeyPriority`); letzte Diagnosedaten in `%LOCALAPPDATA%\Atlas\Logs\Diagnose\atlas-diagnosemodus.txt` | nein | Kontrollkästchen; Taste auf der Seite „Tastenkonflikte“ | #479 |')
[void]$Table.AppendLine('| Allgemein | Einrichtung mit Prüfliste (`ui.setupChecklist`): Fenster „Atlas-Einrichtung“ beim IDE-Start zeigen, solange nicht alles grün ist (beim ersten Start immer); prüft Server (gefunden, gestartet, Version passend), Delphi-Version und Plattform, Index der Projektgruppe je Projekt, Bibliotheks-Cache, Error Insight gegen doppelte Meldungen und Tastenkonflikte, jeder gelbe oder rote Punkt mit Knopf; aus = nur auf Abruf (*Atlas › Einrichtung prüfen …*, Befehlspalette, Zeile „Einrichtung“ im Statusfeld) | an | Plugin (Registry `SetupChecklist`; schon einmal gezeigt in `SetupChecklistSeen`) | nein | Kontrollkästchen, auch im Fenster selbst | #625 |')
[void]$Table.AppendLine('| Tastenkonflikte | Tastenkürzel-Übersicht (#520): Menüeintrag *Atlas › Tastenkürzel-Übersicht…* und Befehl der Befehlspalette (`keys.overview`) mit allen Kürzeln aus IDE, Atlas und anderen Erweiterungen, Konflikten in Rot und HTML-Export; beim Start die Atlas-Tasten prüfen und jeden Konflikt einmal in der Meldungsansicht melden (`keys.startupCheck`) | an, an | Plugin (Registry `KeyOverview`, `KeyStartupCheck`); Export in `%LOCALAPPDATA%\Atlas\Tastenkuerzel.html` | nein | Kontrollkästchen, Kontrollkästchen | #520 |')
[void]$Table.AppendLine('| Allgemein | Abgesicherter Start nach einem Absturz: Rückfrage (`safeMode.askAfterCrash`), ohne Rückfrage nach zwei Abstürzen (`safeMode.autoAfterRepeatedCrash`), Taste beim Laden (`safeMode.startupKey`: shift, ctrl, none), längste Ladezeit (`safeMode.startupTimeoutMs`), gemerkte Einstellungsstände (`safeMode.keepSettingsHistory`) | an, an, shift, 10000, 5 | Plugin (Registry `SafeAskAfterCrash`, `SafeAutoAfterRepeatedCrash`, `SafeStartupKey`, `SafeStartupTimeoutMs`, `SafeKeepSettingsHistory`); Kommandozeile `-AtlasSafeMode`, Umgebungsvariable `ATLAS_SAFE_MODE=1` | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Zahl (1000–120000), Zahl (0–50) | #722 |')
[void]$Table.AppendLine('| Allgemein | Atlas-Änderungen über mehrere Dateien zurücknehmen: an/aus (`undo.multiFile`), Anzahl Sätze (`undo.multiFile.depth`), über Neustarts sichern (`undo.multiFile.persist`) bis höchstens MB (`undo.multiFile.maxSizeMb`), bei Konflikten (`undo.multiFile.onConflict`: partial, abort), neu angelegte Dateien (`undo.multiFile.newFiles`: recycleBin, delete, keep), Tasten Zurücknehmen und Wiederherstellen | an, 20, an, 50, partial, recycleBin, Strg+Alt+Z, Strg+Alt+Umschalt+Z | Plugin (Registry `UndoMultiFile`, `UndoMultiFileDepth`, `UndoMultiFilePersist`, `UndoMultiFileMaxSizeMb`, `UndoMultiFileOnConflict`, `UndoMultiFileNewFiles`, `UndoKey`, `RedoKey`); Sicherung in `%LOCALAPPDATA%\Atlas\undo` | nein | Kontrollkästchen, Zahl (1–200), Kontrollkästchen, Zahl (1–1024), Auswahl, Auswahl, Tastenkürzel, Tastenkürzel | #721 |')
[void]$Table.AppendLine('| Allgemein | Nach Zustimmung beim ersten Start höchstens einmal täglich auf eine neue Atlas-Version prüfen (`updates.check`); übertragen werden nur Atlas- und IDE-Version, ein Hinweis erscheint in der Meldungsansicht und als gelbe Zeile „Version“ im Statusfeld und in der Zustandskachel | aus | Plugin (Registry `UpdatesCheck`); Zustand (auch die gefundene neue Version) in `%LOCALAPPDATA%\Atlas\updates.json` | nein | Kontrollkästchen | #495 |')
[void]$Table.AppendLine('| Allgemein | Fehlerbericht (*Atlas › Fehlerbericht erstellen…*) anonymisieren: Pfade unter dem Projekt zu `<ws>`, andere Pfade zu `<pfad>`, Benutzername und Bezeichner im Protokoll ersetzen (`diagnostics.bugReport.anonymize`) | an | Plugin (Registry `BugReportAnonymize`) | nein | Kontrollkästchen | #108 |')
[void]$Table.AppendLine('| Editor | Zwischen Unit und Testunit wechseln: Code Lens über der Zeile `unit …;` (`codeLens.testUnit`) und Tastenkürzel (Befehl auch im Atlas-Menü, Kontextmenü und in der Befehlspalette) | an, keins | Plugin (Registry `CodeLensTestUnit`, `TestUnitKey`) | nein | Kontrollkästchen, Tastenkürzel | #189 |')
[void]$Table.AppendLine('| Units suchen | Fenster „Units suchen“ von Atlas (`unitSearch.enabled`); aus: Strg+F12 bleibt beim IDE-Dialog | an | Plugin (Registry `UnitSearchEnabled`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Strg+F12 und *Ansicht › Units* öffnen das Atlas-Fenster; mit Umschalt bzw. Befehl *IDE-Dialog Units suchen* der IDE-Dialog (`unitSearch.replaceIdeDialog`) | an | Plugin (Registry `UnitSearchReplaceIdeDialog`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Eigenes Tastenkürzel für das Fenster (`unitSearch.key`) | keins | Plugin (Registry `UnitSearchKey`) | nein | Tastenkürzel | #777 |')
[void]$Table.AppendLine('| Units suchen | Pfadanzeige: relativ zur Projektgruppe, in der Mitte gekürzt oder absolut (`unitSearch.pathStyle`) | relative | Plugin (Registry `UnitSearchPathStyle`) | nein | Auswahlliste | #777 |')
[void]$Table.AppendLine('| Units suchen | Gruppierung: Projekt, Ordner oder flach (`unitSearch.groupBy`) | project | Plugin (Registry `UnitSearchGroupBy`) | nein | Auswahlliste | #777 |')
[void]$Table.AppendLine('| Units suchen | Eingeklappte Gruppen je Projektgruppe merken (`unitSearch.rememberCollapsed`) | an | Plugin (Registry `UnitSearchRememberCollapsed`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Chipzeile Herkunft und Art (`unitSearch.filters`) | an | Plugin (Registry `UnitSearchFilters`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Vorgewählte Herkunft ohne gemerkte Wahl: Projektgruppe, aktives Projekt, Suchpfad, Bibliothek (`unitSearch.defaultScope`) | group | Plugin (Registry `UnitSearchDefaultScope`) | nein | Auswahlliste | #777 |')
[void]$Table.AppendLine('| Units suchen | Tippsyntax `p:` und `t:` im Suchfeld (`unitSearch.filterSyntax`) | an | Plugin (Registry `UnitSearchFilterSyntax`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Vorschau rechts, F4 schaltet um (`unitSearch.preview`) | an | Plugin (Registry `UnitSearchPreview`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Formularskizze in der Vorschau (`unitSearch.preview.form`) | an | Plugin (Registry `UnitSearchPreviewForm`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | „Verwendet von“ in der Vorschau (`unitSearch.preview.usedBy`) | an | Plugin (Registry `UnitSearchPreviewUsedBy`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Häkchen und Mehrfachauswahl (`unitSearch.multiSelect`) | an | Plugin (Registry `UnitSearchMultiSelect`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Aktionsleiste (`unitSearch.actions`) | an | Plugin (Registry `UnitSearchActions`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Units suchen | Aktion „In uses aufnehmen“ (`unitSearch.actions.addUses`) | an | Plugin (Registry `UnitSearchActionsAddUses`) | nein | Kontrollkästchen | #777 |')
[void]$Table.AppendLine('| Willkommensseite | Atlas-Bereiche auf der Willkommensseite (`welcomePage.enabled`, Schnellschalter), anzeigen in (`welcomePage.host`: welcomePage, dockWindow = Fenster „Atlas-Start“), Atlas-Layout (`welcomePage.layout`: off, atlas; mit Sicherung des bisherigen Layouts, *Atlas › Atlas-Layout anwenden/zurücksetzen*), Kopf mit Symbol und Version (`welcomePage.header`), Grußzeile (`welcomePage.greeting`), Suchfeld im Kopf (`welcomePage.search`), Gruppe „Symbole“ darin (`welcomePage.search.symbols`, braucht laufenden Server), Taste für das Suchfeld (`welcomePage.search.key`, nur auf der Willkommensseite), Karte „Neu in Atlas“ (`welcomePage.whatsNew`: off = nie, afterUpdate = einmalig nach einem Update, always = immer), Bereich „Projekte“ mit Zustand je Projekt (`welcomePage.projectStatus`), höchstens so viele Projekte (`welcomePage.maxProjects`, 1–30), Branch und Änderungen frisch abfragen (`welcomePage.refreshVcs`), Bereich „Nicht gesichert“ mit nicht Committetem, nicht Gepushtem und Stashes je Projekt (`welcomePage.unsaved`), erst ab so vielen Stunden zeigen (`welcomePage.unsaved.minAgeHours`, 0–8760), gelb ab (`welcomePage.unsaved.warnHours`, 0–8760), rot ab (`welcomePage.unsaved.alertHours`, 0–8760, nie unter warnHours), Bereich ausblenden, wenn alles gesichert ist (`welcomePage.unsaved.hideWhenClean`; sonst Zeile „Alles gesichert“), Zustandskachel „Atlas“ mit Server, Version, Index, Einrichtung und Diagnosemodus (`welcomePage.statusTile`), Kachel nur bei einer gelben oder roten Zeile (`welcomePage.statusTile.onlyProblems`) | an, welcomePage, off, an, an, an, an, Strg+E, afterUpdate, an, 8, an, an, 0, 24, 72, aus, an, aus | Plugin (Registry `WelcomePage`, `WelcomePageHost`, `WelcomePageLayout`, `WelcomePageHeader`, `WelcomePageGreeting`, `WelcomePageSearch`, `WelcomePageSearchSymbols`, `WelcomePageSearchKey`, `WelcomePageWhatsNew`, `WelcomePageProjectStatus`, `WelcomePageMaxProjects`, `WelcomePageRefreshVcs`, `WelcomePageUnsaved`, `WelcomePageUnsavedMinAgeHours`, `WelcomePageUnsavedWarnHours`, `WelcomePageUnsavedAlertHours`, `WelcomePageUnsavedHideWhenClean`, `WelcomePageStatusTile`, `WelcomePageStatusTileOnlyProblems`; gesehene Version in `WhatsNewSeen`); Sicherung in `%LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json`, Projektzustand (auch Abschnitt `unsaved`) in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json`, letzter Index-Stand der Kachel („Stand vom …“) in `%LOCALAPPDATA%\Atlas\index-state.json` | nein | Kontrollkästchen, Auswahl, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Tastenfeld, Auswahl, Kontrollkästchen, Zahl (1–30), Kontrollkästchen, Kontrollkästchen, Zahl (0–8760), Zahl (0–8760), Zahl (0–8760), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen | #753, #760, #756, #592, #762, #754 |')
$TableText = $Table.ToString().Replace("`r`n", "`n")

# --- Wächter: Schlüssel im Parser ---
$Problems = New-Object System.Collections.Generic.List[string]
$SchemaKeys = @($Schema['properties'].Keys | Where-Object { $_ -ne '$schema' } | Sort-Object)
$ParserText = [IO.File]::ReadAllText($ParserPath, $Utf8).Replace("`r`n", "`n")
$Starts = [regex]::Matches($ParserText, "Key = 'delphiVersion'")
if ($Starts.Count -lt 2) { $Problems.Add('Parser: Validierung und Schichtung nicht gefunden') }
foreach ($Start in $Starts) {
    $Stop = $ParserText.IndexOf("`nend;", $Start.Index)
    $Chain = $ParserText.Substring($Start.Index, $Stop - $Start.Index)
    $Keys = @([regex]::Matches($Chain, "Key = '([A-Za-z]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $Line = $ParserText.Substring(0, $Start.Index).Split("`n").Count
    foreach ($Key in $SchemaKeys) { if ($Keys -cnotcontains $Key) { $Problems.Add("Parser Zeile ${Line}: Schlüssel ""$Key"" aus dem Schema fehlt") } }
    foreach ($Key in $Keys) { if ($SchemaKeys -cnotcontains $Key) { $Problems.Add("Parser Zeile ${Line}: Schlüssel ""$Key"" fehlt im Schema") } }
}
foreach ($Name in $SchemaKeys) {
    $P = $Schema['properties'][$Name]
    if (Has $P 'properties') {
        foreach ($Sub in $P['properties'].Keys) {
            if (-not $ParserText.Contains("'$Sub'")) { $Problems.Add("Parser: ""$Name.$Sub"" aus dem Schema wird nicht gelesen") }
        }
    }
    foreach ($Meta in 'x-page', 'x-control', 'x-issue', 'x-scope') {
        if (-not (Has $P $Meta)) { $Problems.Add("Schema: ""$Name"" ohne $Meta") }
    }
    if ((Has $P 'x-scope') -and ('global', 'project' -cnotcontains $P['x-scope'])) { $Problems.Add("Schema: ""$Name"" mit x-scope ""$($P['x-scope'])""; erlaubt sind global und project") }
    if (Has $P 'properties') {
        foreach ($Sub in $P['properties'].Keys) {
            $S = $P['properties'][$Sub]
            if ((Has $S 'x-scope') -and ('global', 'project' -cnotcontains $S['x-scope'])) { $Problems.Add("Schema: ""$Name.$Sub"" mit x-scope ""$($S['x-scope'])""; erlaubt sind global und project") }
        }
    }
}

# --- Schreiben oder prüfen ---
$Targets = @(
    @{ Path = $DocPath; Text = $Text; Name = 'docs/Konfiguration.md' },
    @{ Path = $TablePath; Text = $TableText; Name = 'docs/Einstellungen.md' }
)
foreach ($Target in $Targets) {
    $Current = if (Test-Path $Target.Path) { [IO.File]::ReadAllText($Target.Path, $Utf8).Replace("`r`n", "`n") } else { '' }
    if ($Current -eq $Target.Text) { continue }
    if ($Check) { $Problems.Add("$($Target.Name) ist veraltet: pwsh Tools/Update-ConfigDoc.ps1 ausführen") }
    else {
        [IO.File]::WriteAllText($Target.Path, $Target.Text, $Utf8)
        Write-Host "Geschrieben: $($Target.Path)"
    }
}
# --- Schema für den Einstellungsdialog im Plugin (#227): UTF-8 mit BOM, CRLF ---
$SchemaUnitPath = Join-Path $Root 'Packages/Atlas.IDE.Expert/Source/Core/Settings/Atlas.Core.Settings.SchemaData.pas'
$SchemaLines = [IO.File]::ReadAllText($SchemaPath, $Utf8).TrimStart([char]0xFEFF).Replace("`r`n", "`n").TrimEnd("`n").Split("`n")
$Unit = New-Object System.Text.StringBuilder
foreach ($Line in @(
    'unit Atlas.Core.Settings.SchemaData;', '',
    '// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json;',
    '// nicht von Hand ändern. JSON-Schema von atlas.json für den Einstellungsdialog (#227).', '',
    'interface', '', '/// <summary>Inhalt von atlas.schema.json.</summary>', 'function AtlasSchemaJson: string;', '',
    'implementation', '', 'const', "  Lines: array[0..$($SchemaLines.Count - 1)] of string = (")) { [void]$Unit.Append($Line + "`r`n") }
for ($Index = 0; $Index -lt $SchemaLines.Count; $Index++) {
    $Escaped = $SchemaLines[$Index].Replace("'", "''")
    $Pieces = @()
    for ($At = 0; $At -lt $Escaped.Length; $At += 200) { $Pieces += "'" + $Escaped.Substring($At, [Math]::Min(200, $Escaped.Length - $At)) + "'" }
    if ($Pieces.Count -eq 0) { $Pieces = @("''") }
    $End = if ($Index -eq $SchemaLines.Count - 1) { ');' } else { ',' }
    [void]$Unit.Append('    ' + ($Pieces -join ' + ') + $End + "`r`n")
}
foreach ($Line in @('', 'function AtlasSchemaJson: string;', 'var', '  Line: string;', 'begin', "  Result := '';",
    '  for Line in Lines do', '    Result := Result + Line + #10;', 'end;', '', 'end.')) { [void]$Unit.Append($Line + "`r`n") }
$UnitText = $Unit.ToString()
$CurrentUnit = if (Test-Path $SchemaUnitPath) { [IO.File]::ReadAllText($SchemaUnitPath, $Utf8).TrimStart([char]0xFEFF) } else { '' }
if ($CurrentUnit -ne $UnitText) {
    if ($Check) { $Problems.Add('Atlas.Core.Settings.SchemaData.pas ist veraltet: pwsh Tools/Update-ConfigDoc.ps1 ausführen') }
    else {
        [IO.File]::WriteAllText($SchemaUnitPath, $UnitText, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "Geschrieben: $SchemaUnitPath"
    }
}

# --- Ort der Schlüssel für den Server: UTF-8 mit BOM, CRLF ---
$ScopeUnitPath = Join-Path $Root 'Packages/Atlas.Common/Source/Configuration/Internals/Atlas.Common.Configuration.Internals.ScopeData.pas'
$GlobalPaths = New-Object System.Collections.Generic.List[string]
$ProjectPaths = New-Object System.Collections.Generic.List[string]
foreach ($Name in $Schema['properties'].Keys) {
    if ($Name -eq '$schema') { continue }
    $P = $Schema['properties'][$Name]
    $Scope = Scope-Of $P ''
    $Mixed = $false
    if (Has $P 'properties') {
        foreach ($Sub in $P['properties'].Keys) { if ((Scope-Of $P['properties'][$Sub] $Scope) -ne $Scope) { $Mixed = $true } }
    }
    if ($Mixed) {
        foreach ($Sub in $P['properties'].Keys) {
            if ((Scope-Of $P['properties'][$Sub] $Scope) -eq 'global') { $GlobalPaths.Add("$Name.$Sub") } else { $ProjectPaths.Add("$Name.$Sub") }
        }
    }
    elseif ($Scope -eq 'global') { $GlobalPaths.Add($Name) }
    else { $ProjectPaths.Add($Name) }
}
function Pascal-List([string] $Name, $Items) {
    $Lines = @("  $Name`: array[0..$($Items.Count - 1)] of string = (")
    for ($Index = 0; $Index -lt $Items.Count; $Index++) {
        $End = if ($Index -eq $Items.Count - 1) { ');' } else { ',' }
        $Lines += "    '$($Items[$Index])'$End"
    }
    return $Lines
}
$ScopeLines = @(
    'unit Atlas.Common.Configuration.Internals.ScopeData;', '',
    '// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json (x-scope);',
    '// nicht von Hand ändern. Ort jedes Schlüssels: global = %APPDATA%\Atlas\settings.json,',
    '// Projekt = atlas.json. Gemischte Objekte stehen je Glied als "objekt.glied" da.', '',
    'interface', '', 'const', '  /// <summary>Schlüssel für alle Projekte (settings.json).</summary>') +
    (Pascal-List 'GlobalSettingPaths' $GlobalPaths) +
    @('  /// <summary>Schlüssel des Projekts (atlas.json).</summary>') +
    (Pascal-List 'ProjectSettingPaths' $ProjectPaths) +
    @('', 'implementation', '', 'end.')
$ScopeText = ($ScopeLines -join "`r`n") + "`r`n"
$CurrentScope = if (Test-Path $ScopeUnitPath) { [IO.File]::ReadAllText($ScopeUnitPath, $Utf8).TrimStart([char]0xFEFF) } else { '' }
if ($CurrentScope -ne $ScopeText) {
    if ($Check) { $Problems.Add('Atlas.Common.Configuration.Internals.ScopeData.pas ist veraltet: pwsh Tools/Update-ConfigDoc.ps1 ausführen') }
    else {
        [IO.File]::WriteAllText($ScopeUnitPath, $ScopeText, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "Geschrieben: $ScopeUnitPath"
    }
}

if ($Problems.Count -gt 0) {
    foreach ($Problem in $Problems) { Write-Error $Problem -ErrorAction Continue }
    exit 1
}
Write-Host 'Schema, Parser, Schema-Unit und Doku stimmen überein.'
exit 0
