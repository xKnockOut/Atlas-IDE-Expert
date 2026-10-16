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
[void]$Out.AppendLine('`atlas.json` liegt im Repository und gilt für alle im Team (#486). Zugangsdaten (Schlüssel wie `token`, `password`, `user` auf jeder Ebene, Adressen wie `https://user:pw@…` oder `?token=…`) und absolute Pfade (Laufwerk oder UNC) in den Pfad-Einstellungen (`project`, `testUnits.folder`, `testUnits.project`, `exclude`, `index.exclude`, `overrides[].files`) werden beim Lesen ignoriert und als Warnung gemeldet. Glob-Muster ab dem Projektordner (`/Generated/**`) und relative Pfade (`..\Tests`) bleiben erlaubt. Die globale `settings.json` ist persönlich und davon ausgenommen. Die Team-Einstellungen des Plugins stehen in der eigenen Projektdatei `.atlas` (siehe [Einstellungen.md](Einstellungen.md)).')
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
[void]$Table.AppendLine('| Compiler | Builds für Claude Code (`compiler.mcpBuild`, Schnellschalter): Das MCP-Werkzeug `build_project` darf offene Projekte in dieser IDE über IOTAProjectBuilder bauen (make, build, check; Konfiguration und Plattform nur für diesen Build) und bekommt Ergebnis und Compilermeldungen, auch in der Starter Edition ohne Kommandozeilen-Compiler. Abgelehnt mit Grund, solange der Debugger, ein anderer Build oder die Compilerprüfung läuft; aus = die IDE nimmt keine Aufträge an | an | Plugin (Registry `McpBuild`) | nein | Kontrollkästchen | #261 |')
[void]$Table.AppendLine('| Compiler | DUnitX-Tests ausführen (#69, `tests.run`, Schnellschalter): Befehle „Tests ausführen“ (*Atlas.RunTests*) und „Fehlgeschlagene Tests erneut ausführen“ (*Atlas.RunFailedTests*) in der Befehlspalette; Testprojekt ist das aktive bzw. eines der Projektgruppe, dessen Hauptdatei `DUnitX.TestFramework` verwendet (für einen Test das Testprojekt, das seine Testunit enthält); bei mehreren fragt Atlas einmal und merkt sich die Wahl für genau diese Kandidaten (#585, lokal in `%LOCALAPPDATA%\Atlas\test-projects.json`); Plattform und Konfiguration aus dem Testprojekt; Ergebnis über den XML-Logger von DUnitX, fehlgeschlagene Tests als Probleme an der Testmethode (Quelle `DUnitX`, erwarteter und tatsächlicher Wert) und in der Meldungsansicht; aus = Befehle, Code Lens und Lauf nach dem Build verschwinden | an | Plugin (Registry `TestRun`) | nein | Kontrollkästchen | #69 |')
[void]$Table.AppendLine('| Compiler | Vor den Tests bauen (`tests.buildFirst`): „Tests ausführen“ baut das Testprojekt vorher (make) wie `build_project`; aus = die vorhandene Test-EXE läuft ohne Compiler | an | Plugin (Registry `TestsBuildFirst`) | nein | Kontrollkästchen | #69 |')
[void]$Table.AppendLine('| Compiler | Tests nach dem Build (`tests.afterBuild`, Schnellschalter): nach jedem erfolgreichen Build eines DUnitX-Testprojekts durch den Benutzer laufen dessen Tests (Compile-Ereignisse #527); nicht nach der Hintergrundprüfung und nicht nach Builds für Claude Code | aus | Plugin (Registry `TestsAfterBuild`) | nein | Kontrollkästchen | #69 |')
[void]$Table.AppendLine('| Compiler | Build nur ohne Warnungen und Hinweise erfolgreich (`build.zeroHints`): Vorgriff auf #530; wirkt bisher nur auf „Tests nach dem Build“, die dann nur nach einem Build ohne Warnungen und Hinweise laufen | aus | Plugin (Registry `BuildZeroHints`) | nein | Kontrollkästchen | #530 |')
[void]$Table.AppendLine('| Compiler | Startprofile (#575, `startProfiles.enabled`, Schnellschalter): Befehl „Startprofil: …“ (*Atlas.StartProfile*, Befehlspalette) und Klick auf das Feld in der Statusleiste wählen für das aktive Projekt ein Profil aus `startProfiles` der Projektdatei `.atlas` (gemeinsam, braucht `teamFile.enabled`) oder ein persönliches; Atlas setzt Parameter, Arbeitsordner, Host-Anwendung und Umgebungsvariablen der aktiven Konfiguration und Plattform (wie *Start › Parameter*), *Start* und *Ohne Debugger starten* nutzen sie dann; das aktive Profil gilt je Projekt und wird bei Wechsel von Projekt, Konfiguration oder Plattform wieder gesetzt; „Kein Startprofil“ stellt die Startoptionen von vor dem ersten Profil wieder her; „Aktuelle Startoptionen als persönliches Profil speichern …“; Feld „Startprofil: <Name>“ in der Statusleiste, sobald das Projekt Profile hat (`startProfiles.statusField`, Schnellschalter); aus = Befehl, Feld und Tipp verschwinden, die Startoptionen bleiben, wie sie sind | an, an | Plugin (Registry `StartProfiles`, `StartProfilesStatusField`); persönliche Profile, aktives Profil und die Startoptionen von vorher je Projekt nur lokal in `%LOCALAPPDATA%\Atlas\startprofiles\<Schlüssel>.json`; gemeinsame in `.atlas` | nein | Kontrollkästchen, Kontrollkästchen | #575 |')
[void]$Table.AppendLine('| Debuggen | Einzelnen Test debuggen (#585, `tests.debug`, Schnellschalter): Befehle „Test am Cursor debuggen“ (*Atlas.DebugTest*) und „Test am Cursor ausführen“ (*Atlas.RunTest*, mit `tests.run`) in der Befehlspalette, Einträge „Test debuggen“/„Test ausführen“ im Kontextmenü des Editors und Marke „Debuggen“ der Code Lens an `[TestFixture]`, `[Test]` und je `[TestCase]`; Atlas baut das Testprojekt (wie „Tests ausführen“), setzt über die Startprofile (#575) vorübergehend die Startparameter `--run:<Unit.Fixture.Methode[.Fall]>` (vorhandene Parameter bleiben, `--run`, `--include`, `--exclude`, `--xmlfile` und `--exitbehavior` weichen) und startet es im Debugger; danach gelten aktives Projekt und Startparameter wie vorher (auch nach einem Absturz beim nächsten Start), das Ergebnis erscheint wie bei „Tests ausführen“. Braucht „Tests ausführen“; aus = Befehl, Eintrag, Marke und Tipp verschwinden | an | Plugin (Registry `TestDebug`) | nein | Kontrollkästchen | #585 |')
[void]$Table.AppendLine('| Debuggen | Beim Test-Debuggen am Anfang der Methode anhalten (`debug.testBreakAtStart`): einmaliger Haltepunkt auf der ersten Anweisung der Testmethode, den Atlas nach dem ersten Halt wieder entfernt (ein eigener Haltepunkt dort bleibt unberührt); nicht beim Debuggen einer ganzen Fixture | an | Plugin (Registry `TestBreakAtStart`) | nein | Kontrollkästchen | #585 |')
[void]$Table.AppendLine('| Baseline | `atlas-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |')
[void]$Table.AppendLine('| Projektdatei | Projektdatei `.atlas` (#486) lesen (`teamFile.enabled`, Schnellschalter): Einstellungen des Plugins für alle im Team, im Ordner der .dproj, sonst in der Wurzel des Repositorys (nächster Ordner mit `.git`); JSON mit Kommentaren und `version` (1) mit `naming` (Präfixe `field`, `parameter`, `local`, #452), `snippets` (Ordner mit Projekt-Vorlagen, #51), `formatFunctions` (`name`, `formatIndex`, #451), `sqlTargets` (#462), `fileMethods` (#478), `mainThreadExceptions` (#484), `startProfiles` (`name`, `parameters`, `workingDir`, `host`, `environment`, #575), `ci` (`provider` jenkins, `url`, `job`, `multibranch`, #763) und `tracker` (`provider` github oder youtrack, `url`, `project`, #765). Werte aus `.atlas` haben Vorrang vor den persönlichen (Listen ergänzen sich), der Reiter *Projektdatei* zeigt jeden mit „aus .atlas“. Zugangsdaten, absolute Pfade und Pfade außerhalb des Repositorys werden ignoriert (ein Startprofil damit ganz), fehlerhafte Dateien und ignorierte Einträge in der Meldungsansicht gemeldet; dann gelten die persönlichen Einstellungen. Befehl *Projektdatei .atlas öffnen* (*Atlas.TeamFile*, Befehlspalette, Knopf auf dem Reiter) legt die Datei mit Gerüst an und öffnet sie | an | Plugin (Registry `TeamFile`); Datei `.atlas` im Repository | nein | Kontrollkästchen, Werte „aus .atlas“, Knopf „Projektdatei öffnen“ | #486 |')
[void]$Table.AppendLine('| Baseline | Unterdrückungen `lsp-ignore` | – | `--suppression-stats` | nein | Übersicht je Regel (nur Anzeige) | #147 |')
[void]$Table.AppendLine('| Speicher | Index-Cache löschen | – | `--clear-cache`, Befehl `atlas.server.clearIndex` (löschen und neu indizieren), `atlas.server.rebuildIndex` (nur neu indizieren) | nein | Knöpfe „Index löschen“ und „Index neu aufbauen“ | #184, #492 |')
[void]$Table.AppendLine('| Allgemein | Atlas-Feld in der Statusleiste (`statusField.enabled`), Kurztext (`statusField.showSummary`), Schnellschalter öffnen mit (`statusField.openToggles`: both, rightClick, doubleClick), ausgeblendete Zeilen (`statusField.hidden`) | an, an, both, – | Plugin (Registry `StatusField`, `StatusFieldSummary`, `StatusFieldToggles`, `StatusFieldHidden`) | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Textfeld mit Kennungen | #591 |')
[void]$Table.AppendLine('| Allgemein | Fortschritt beim Aufbau des Symbol-Index (`statusField.indexProgress`: statusField, menu, off); mit abgeschaltetem Statusfeld steht er im Menütitel | statusField | Plugin (Registry `IndexProgressPlace`) | nein | Auswahl | #492, #591 |')
[void]$Table.AppendLine('| Allgemein | Schnellschalter (#604): Fenster über dem Statusfeld (Rechtsklick oder Doppelklick) und Tastenkürzel; Schalter = jede boolesche Einstellung mit `x-quickToggle` (Plugin-Katalog und `atlas.schema.json`) | Strg+Umschalt+Alt+A | Plugin (Registry `QuickToggleKey`, `QuickToggleKeyPriority`) | nein | Taste auf der Seite „Tastenkonflikte“; „Alles aus für diese Sitzung“ ändert keine Einstellung | #604 |')
[void]$Table.AppendLine('| Allgemein | Diagnosemodus (`diagnosticMode.enabled`, Schnellschalter): andockbares Fenster „Atlas-Diagnose“ mit der Dauer jedes Schritts der letzten Abfrage (Kontext, je Quelle mit Namen, Filtern und Sortieren, Zeichnen, bis zur Liste, Anzahl der Einträge) sowie Mittelwert und Maximum der letzten 50 Abfragen; Überschreitungen des Budgets aus #409 in Warnfarbe; „Bericht kopieren“ ohne Quelltext, Dateinamen nur mit Häkchen; gelbe Zeile im Statusfeld; Tastenkürzel (Strg+Alt+Umschalt+A gehört den Schnellschaltern) | aus, Strg+Umschalt+Alt+D | Plugin (Registry `DiagnosticMode`, `DiagnosticModeKey`, `DiagnosticModeKeyPriority`); letzte Diagnosedaten in `%LOCALAPPDATA%\Atlas\Logs\Diagnose\atlas-diagnosemodus.txt` | nein | Kontrollkästchen; Taste auf der Seite „Tastenkonflikte“ | #479 |')
[void]$Table.AppendLine('| Allgemein | Einrichtung mit Prüfliste (`ui.setupChecklist`): Fenster „Atlas-Einrichtung“ beim IDE-Start zeigen, solange nicht alles grün ist (beim ersten Start immer); prüft Server (gefunden, gestartet, Version passend), Delphi-Version und Plattform, Index der Projektgruppe je Projekt, Bibliotheks-Cache, Error Insight gegen doppelte Meldungen und Tastenkonflikte, jeder gelbe oder rote Punkt mit Knopf; aus = nur auf Abruf (*Atlas › Einrichtung prüfen …*, Befehlspalette, Zeile „Einrichtung“ im Statusfeld) | an | Plugin (Registry `SetupChecklist`; schon einmal gezeigt in `SetupChecklistSeen`) | nein | Kontrollkästchen, auch im Fenster selbst | #625 |')
[void]$Table.AppendLine('| Tastenkonflikte | Tastenkürzel-Übersicht (#520): Menüeintrag *Atlas › Tastenkürzel-Übersicht…* und Befehl der Befehlspalette (`keys.overview`) mit allen Kürzeln aus IDE, Atlas und anderen Erweiterungen, Konflikten in Rot und HTML-Export; beim Start die Atlas-Tasten prüfen und jeden Konflikt einmal in der Meldungsansicht melden (`keys.startupCheck`) | an, an | Plugin (Registry `KeyOverview`, `KeyStartupCheck`); Export in `%LOCALAPPDATA%\Atlas\Tastenkuerzel.html` | nein | Kontrollkästchen, Kontrollkästchen | #520 |')
[void]$Table.AppendLine('| Allgemein | Tastenkürzel-Tipps (`shortcutTips.enabled`, Schnellschalter): wer eine IDE- oder Atlas-Aktion mit Kürzel per Maus (Hauptmenü, Kontextmenü, Werkzeugleiste, Befehlspalette) aufruft, sieht 4 s lang unten rechts im Editor das Kürzel mit Tastenkappen, „Nicht mehr zeigen“ und „Alle Kürzel“; höchstens ein Tipp je Aktion und Tag, keiner nach dreimaliger Nutzung des Kürzels, nicht bei angehaltener Debug-Sitzung oder offenem modalem Dialog, höchstens alle 30 s; für welche Befehle (`shortcutTips.scope`: atlas = nur Atlas-Befehle, all = auch die der IDE); Zählung je Befehl auch für die Spalte „Selten per Tastatur“ der Tastenkürzel-Übersicht und die Karte „Atlas entdecken“ (#757); Titel des Tipps aus `tips.json`, wenn es dort einen Tipp zum Befehl gibt | an, all | Plugin (Registry `ShortcutTips`, `ShortcutTipsScope`); Zählung je Befehl nur lokal in `%LOCALAPPDATA%\Atlas\usage.json` (#757), letzter Tipp und „Nicht mehr zeigen“ je Befehl in `%LOCALAPPDATA%\Atlas\shortcut-tips.json` | nein | Kontrollkästchen, Auswahl | #600 |')
[void]$Table.AppendLine('| Allgemein | Benachrichtigungszentrale (`notifications.enabled`, Schnellschalter): Build fertig, Hintergrundprüfung, neu geladene Dateien, Server-Neustarts und -Meldungen sowie Tastenkürzel-Tipps landen als Einträge in einer Liste über dem Atlas-Statusfeld (Klick auf die Zahl im Feld, Befehl *Atlas.Notifications*, Tastenkürzel); neueste zuerst mit Symbol nach Schwere, Titel, Text, Quelle und Uhrzeit, ungelesene hinterlegt, Aktionen wie „Zum Fehler“, „Vergleichen“, „Protokoll öffnen“ als Knöpfe; „Alle gelesen“, „Liste leeren“, Filter nach Quelle; gleichartige Hinweise innerhalb von 10 s werden zusammengefasst („3 × Server neu gestartet“); die Zahl im Statusfeld zählt die ungelesenen in der Farbe des schwersten; gilt für die IDE-Sitzung; aus: jede Funktion zeigt ihre Hinweise wie bisher, nichts wird gesammelt | an | Plugin (Registry `Notifications`) | nein | Kontrollkästchen | #601 |')
[void]$Table.AppendLine('| Allgemein | Verhalten je Quelle (`notifications.sources`): `quelle=verhalten`, kommagetrennt; Quellen build, check, reload, server, shortcutTips (künftige wie der Build-Server #763 kommen dazu); Verhalten show = einblenden und sammeln, collect = nur sammeln (keine eigene Einblendung bzw. keine Zeile im Meldungsfenster), off = weder noch; auch im Kontextmenü eines Eintrags; „Build fertig“ hat noch keine eigene Einblendung (#535), dort wirken show und collect gleich | leer (alle show) | Plugin (Registry `NotificationsSources`) | nein | Auswahl (Quelle, Verhalten) | #601 |')
[void]$Table.AppendLine('| Allgemein | Höchstzahl der Einträge in der Liste der Benachrichtigungen (`notifications.maxEntries`, 10–1000); ältere fallen weg | 200 | Plugin (Registry `NotificationsMaxEntries`) | nein | Zahl | #601 |')
[void]$Table.AppendLine('| Allgemein | Abgesicherter Start nach einem Absturz: Rückfrage (`safeMode.askAfterCrash`), ohne Rückfrage nach zwei Abstürzen (`safeMode.autoAfterRepeatedCrash`), Taste beim Laden (`safeMode.startupKey`: shift, ctrl, none), längste Ladezeit (`safeMode.startupTimeoutMs`), gemerkte Einstellungsstände (`safeMode.keepSettingsHistory`) | an, an, shift, 10000, 5 | Plugin (Registry `SafeAskAfterCrash`, `SafeAutoAfterRepeatedCrash`, `SafeStartupKey`, `SafeStartupTimeoutMs`, `SafeKeepSettingsHistory`); Kommandozeile `-AtlasSafeMode`, Umgebungsvariable `ATLAS_SAFE_MODE=1` | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Zahl (1000–120000), Zahl (0–50) | #722 |')
[void]$Table.AppendLine('| Allgemein | Atlas-Änderungen über mehrere Dateien zurücknehmen: an/aus (`undo.multiFile`), Anzahl Sätze (`undo.multiFile.depth`), über Neustarts sichern (`undo.multiFile.persist`) bis höchstens MB (`undo.multiFile.maxSizeMb`), bei Konflikten (`undo.multiFile.onConflict`: partial, abort), neu angelegte Dateien (`undo.multiFile.newFiles`: recycleBin, delete, keep), Tasten Zurücknehmen und Wiederherstellen | an, 20, an, 50, partial, recycleBin, Strg+Alt+Z, Strg+Alt+Umschalt+Z | Plugin (Registry `UndoMultiFile`, `UndoMultiFileDepth`, `UndoMultiFilePersist`, `UndoMultiFileMaxSizeMb`, `UndoMultiFileOnConflict`, `UndoMultiFileNewFiles`, `UndoKey`, `RedoKey`); Sicherung in `%LOCALAPPDATA%\Atlas\undo` | nein | Kontrollkästchen, Zahl (1–200), Kontrollkästchen, Zahl (1–1024), Auswahl, Auswahl, Tastenkürzel, Tastenkürzel | #721 |')
[void]$Table.AppendLine('| Allgemein | Nach Zustimmung beim ersten Start höchstens einmal täglich auf eine neue Atlas-Version prüfen (`updates.check`); übertragen werden nur Atlas- und IDE-Version, ein Hinweis erscheint in der Meldungsansicht und als gelbe Zeile „Version“ im Statusfeld und in der Zustandskachel | aus | Plugin (Registry `UpdatesCheck`); Zustand (auch die gefundene neue Version) in `%LOCALAPPDATA%\Atlas\updates.json` | nein | Kontrollkästchen | #495 |')
[void]$Table.AppendLine('| Allgemein | Fehlerbericht (*Atlas › Fehlerbericht erstellen…*) anonymisieren: Pfade unter dem Projekt zu `<ws>`, andere Pfade zu `<pfad>`, Benutzername und Bezeichner im Protokoll ersetzen (`diagnostics.bugReport.anonymize`) | an | Plugin (Registry `BugReportAnonymize`) | nein | Kontrollkästchen | #108 |')
[void]$Table.AppendLine('| Vervollständigung | Favoriten anheften (`completion.favorites`, Schnellschalter): Strg+D in der offenen Liste oder Klick auf den Stern, der beim Überfahren einer Zeile erscheint, heftet den Eintrag an bzw. löst ihn; angeheftete Einträge stehen mit Stern links vor allen anderen Gruppen, unabhängig von Lernen und Rangfolge, aber nur, wenn sie zum getippten Präfix passen; je Paar (Typ, Member) wie die lernende Gewichtung, höchstens 5 je Typ (ein sechster ersetzt nichts, die Fußzeile nennt den Grund); Liste mit „Entfernen“ und „Alle entfernen“ auf der Optionsseite | an | Plugin (Registry `Favorites`); Favoriten in `%APPDATA%\Atlas\favorites.json` (Typ, Member, Art, Unit, Signatur, Zeitpunkt; lesbar ohne Server) | nein | Kontrollkästchen, Liste mit Knöpfen | #458 |')
[void]$Table.AppendLine('| Editor | Zwischen Unit und Testunit wechseln: Code Lens über der Zeile `unit …;` (`codeLens.testUnit`) und Tastenkürzel (Befehl auch im Atlas-Menü, Kontextmenü und in der Befehlspalette) | an, keins | Plugin (Registry `CodeLensTestUnit`, `TestUnitKey`) | nein | Kontrollkästchen, Tastenkürzel | #189 |')
[void]$Table.AppendLine('| Editor | Code Lens „Test ausführen“ (`codeLens.tests`, Schnellschalter; gemeinsamer Schlüssel mit „Test debuggen“ #585): hinter `[TestFixture]` und `[Test]`/`[TestCase]` (bzw. der Deklaration registrierter Fixtures und published-Methoden) eine Marke mit dem Ergebnis des letzten Laufs (bestanden grün, fehlgeschlagen rot, während eines Laufs „Tests laufen …“); Klick startet den Test bzw. alle Tests der Fixture; ein `[TestCase]` in eigener Zeile hat eine eigene Marke „Fall ausführen“ (#585); daneben „Debuggen“, wenn „Test debuggen“ an ist. Braucht „Tests ausführen“; aus = keine Marken, weder „Test ausführen“ noch „Debuggen“ | an | Plugin (Registry `CodeLensTests`) | nein | Kontrollkästchen | #69 |')
[void]$Table.AppendLine('| Editor | Code-Metriken (#66): Code Lens hinter dem Kopf jeder implementierten Methode mit Länge, Verschachtelungstiefe, zyklomatischer und kognitiver Komplexität und Parameteranzahl, Werte über dem Grenzwert markiert (`codeLens.metrics`, Schnellschalter; Grenzwerte als `max` der Regeln `metric-*` in atlas.json); Befehl „Metrikbericht des Projekts“ (*Atlas.MetricsReport*, Befehlspalette, abschaltbar mit `metrics.report`, Schnellschalter; aus = der Befehl verschwindet) schreibt den Markdown-Bericht des aktiven Projekts nach `%LOCALAPPDATA%\Atlas\Berichte\Metriken-<Projekt>.md` und öffnet ihn; nach jedem Build (nicht nach einer Hintergrundprüfung) legt das Plugin die Zusammenfassung im Abschnitt `metrics` der Projekt-Zusammenfassung ab (Projektverlauf #758) | an, an | Plugin (Registry `CodeLensMetrics`, umgeleitet nach settings.json `codeLens.metrics`; Registry `MetricsReport`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen, Kontrollkästchen | #66 |')
[void]$Table.AppendLine('| Editor | TODO-Übersicht (#68): Befehle „TODOs des Projekts“ (*Atlas.TodoList*) und „TODOs des Projekts filtern …“ (*Atlas.TodoListFilter*, Kategorie, Person, Unit, Marke, Erledigte) in der Befehlspalette (`todos.list`, Schnellschalter; aus = beide Befehle verschwinden) listen die offenen `// TODO`, `// FIXME` und `{ TODO … }` des aktiven Projekts nach Unit im Ergebnisfenster; Marken als `keywords` der Regel `todo-comment` in atlas.json (Vorgabe `TODO`, `FIXME`), Hinweise im Editor nur mit eingeschalteter Regel; nach jedem Build legt das Plugin die Zählung im Abschnitt `todos` der Projekt-Zusammenfassung ab (Projektverlauf #758) | an, Hinweise aus | Plugin (Registry `TodoList`); Server (atlas.json `rules.todo-comment`: Schweregrad und `keywords`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen; Regel und Marken nur in atlas.json | #68 |')
[void]$Table.AppendLine('| Editor | Baseline für Altprojekte (#97): Befehl „Baseline des Projekts aktualisieren“ (*Atlas.UpdateBaseline*, Befehlspalette, abschaltbar mit `baseline.update`, Schnellschalter; aus = der Befehl verschwindet, die Baseline wirkt weiter) lässt den Server (`atlas.updateBaseline`) alle Dateien des aktiven Projekts prüfen und `atlas-baseline.json` im Arbeitsbereich neu schreiben; vorher nennt er Einträge, deren Datei es nicht mehr gibt, und fragt nach, danach stehen die Zähler (neu, entfernt, unverändert) im Meldungsfenster; nach jedem Build und nach dem Aktualisieren legt das Plugin den Stand der Baseline im Abschnitt `baseline` der Projekt-Zusammenfassung ab (Projektverlauf #758, Einrichtung #759) | an | Plugin (Registry `BaselineUpdate`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen | #97 |')
[void]$Table.AppendLine('| Editor | Persönliche Notizen an Codezeilen (`notes.enabled`, Schnellschalter): *Atlas › Notiz an dieser Zeile…* (Befehlspalette, Atlas-Untermenü im Editor-Kontextmenü; nach Rechtsklick in die Rinne für die angeklickte Zeile) legt eine ein- oder mehrzeilige Notiz an, ein Symbol in der Rinne zeigt sie, Überfahren zeigt den Text; *Atlas › Notizen des Projekts* listet alle im Ergebnisfenster (Datei, Zeile, Text, Doppelklick springt, verwaiste Notizen gesondert); die Notiz folgt ihrer Zeile über Inhalt und je zwei Nachbarzeilen | an | Plugin (Registry `Notes`); Notizen je Projekt in `%LOCALAPPDATA%\Atlas\Notes\<Schlüssel>.json`, nie im Repository | nein | Kontrollkästchen | #545 |')
[void]$Table.AppendLine('| Editor | Benannte Lesezeichen (`bookmarks.named`, Schnellschalter): *Atlas › Lesezeichen setzen…* (Strg+Alt+K, Befehlspalette, Atlas-Untermenü im Editor-Kontextmenü; nach Rechtsklick in die Rinne für die angeklickte Zeile) fragt nach dem Namen und schlägt Methode und Zeilenbeginn vor; ein Band in der Rinne zeigt das Lesezeichen, Überfahren zeigt den Namen; *Atlas › Gehe zu Lesezeichen…* sucht unscharf über Name, Datei und Methode; das Seitenfenster *Atlas › Lesezeichen-Fenster* listet Name, Datei, Methode und Zeilenvorschau mit Filter (Klick oder Enter springt, F2 benennt um, Entf löscht, Ziehen sortiert); das Lesezeichen sucht zuerst seine Methode und dann den Zeilentext darin, fehlt beides, steht es als „nicht gefunden“ in der Liste; aus: alles ruht, die IDE-Lesezeichen bleiben unberührt | an | Plugin (Registry `BookmarksNamed`) | nein | Kontrollkästchen | #622 |')
[void]$Table.AppendLine('| Editor | Lesezeichen im Repository für das Team (`bookmarks.shared`): `atlas-bookmarks.json` neben der .dproj zum Einchecken statt der persönlichen `.atlas-bookmarks.json` (die Atlas lokal in `.git/info/exclude` einträgt); gibt es die Team-Datei noch nicht, gelten zunächst die persönlichen Lesezeichen | aus | Plugin (Registry `BookmarksShared`) | nein | Kontrollkästchen | #622 |')
[void]$Table.AppendLine('| Editor | Tastenkürzel für „Lesezeichen setzen…“ (`bookmarks.key`, Reiter *Befehle*; leer = keins) | Strg+Alt+K | Plugin (Registry `BookmarkKey`) | nein | Tastenkürzel | #622 |')
[void]$Table.AppendLine('| Befehle | Erzeugen-Menü (`keys.generateMenu`, Schnellschalter): Alt+Einfg, *Atlas › Erzeugen…*, Atlas-Untermenü im Editor-Kontextmenü und Befehlspalette (*Atlas.GenerateMenu*) öffnen am Cursor ein Menü mit den Gruppen Erzeugen (Schnellbefehle mit Ortsregel aus #293, „Interface implementieren“, Code-Aktionen der Art refactor), Umschließen (nur mit Markierung) und Vorlagen (Code-Vorlagen mit passendem `context:`); jede Zeile mit Ziffer 1–9 und `/name`, Tippen filtert unscharf, zuletzt gewählte stehen oben, Einträge mit Auswahl (Felder, Methoden) öffnen sie; Entf blendet einen Eintrag aus; aus: die Funktion ruht, Alt+Einfg bleibt frei | an | Plugin (Registry `GenerateMenu`); zuletzt gewählte in `%APPDATA%\Atlas\generate-recent.txt` | nein | Kontrollkästchen | #719 |')
[void]$Table.AppendLine('| Befehle | Tastenkürzel des Erzeugen-Menüs (`keys.generateMenu.key`; leer = keins) | Alt+Einfg | Plugin (Registry `GenerateMenuKey`) | nein | Tastenkürzel | #719 |')
[void]$Table.AppendLine('| Befehle | Gruppen des Erzeugen-Menüs in ihrer Reihenfolge (`keys.generateMenu.groups`: generate, surround, templates; fehlt eine, fehlt sie im Menü) | generate,surround,templates | Plugin (Registry `GenerateMenuGroups`) | nein | Textfeld | #719 |')
[void]$Table.AppendLine('| Befehle | Ausgeblendete Einträge des Erzeugen-Menüs (`keys.generateMenu.hidden`): Kennungen wie `slash:json`, `snippet:tryf`, `action:Titel` oder Namen wie `/json`, `tryf`, kommagetrennt; Entf im Menü ergänzt die Liste | leer | Plugin (Registry `GenerateMenuHidden`) | nein | Textfeld | #719 |')
[void]$Table.AppendLine('| Befehle | Zuletzt gewählte Einträge oben im Erzeugen-Menü, höchstens drei (`keys.generateMenu.recentFirst`) | an | Plugin (Registry `GenerateMenuRecentFirst`) | nein | Kontrollkästchen | #719 |')
[void]$Table.AppendLine('| Befehle | Befehlsnamen (`/ctor`, Kürzel der Vorlage) rechts in den Zeilen des Erzeugen-Menüs (`keys.generateMenu.showCommandNames`) | an | Plugin (Registry `GenerateMenuShowCommandNames`) | nein | Kontrollkästchen | #719 |')
[void]$Table.AppendLine('| Befehle | Tastenkürzel der Liste der Benachrichtigungen (`notifications.key`; leer = keins; Vorrang wie die Editorbefehle) | Strg+Umschalt+Alt+N | Plugin (Registry `NotificationsKey`) | nein | Tastenkürzel | #601 |')
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
[void]$Table.AppendLine('| Willkommensseite | Atlas-Bereiche auf der Willkommensseite (`welcomePage.enabled`, Schnellschalter), anzeigen in (`welcomePage.host`: welcomePage, dockWindow = Fenster „Atlas-Start“), Atlas-Layout (`welcomePage.layout`: off, atlas; mit Sicherung des bisherigen Layouts, *Atlas › Atlas-Layout anwenden/zurücksetzen*), Kopf mit Symbol und Version (`welcomePage.header`), Grußzeile (`welcomePage.greeting`), Suchfeld im Kopf (`welcomePage.search`), Gruppe „Symbole“ darin (`welcomePage.search.symbols`, braucht laufenden Server), Taste für das Suchfeld (`welcomePage.search.key`, nur auf der Willkommensseite), Karte „Neu in Atlas“ (`welcomePage.whatsNew`: off = nie, afterUpdate = einmalig nach einem Update, always = immer), Bereich „Weiterarbeiten“ mit den letzten Arbeitsständen (Reiter, zuletzt bearbeitete Datei und Methode, „Fortsetzen“ öffnet Projekt und Reiter und setzt den Cursor an die letzte Änderung; *Atlas.Continue* in der Palette) (`welcomePage.continue`; aus = kein Bereich, nichts wird mitgeschrieben), höchstens so viele Arbeitsstände (`welcomePage.continue.count`, 1–20), „Neu seit deinem letzten Öffnen“ mit eingehenden Commits zu den eigenen Dateien aus dem lokalen Stand der Remote-Branches (`welcomePage.continue.incoming`), vorher abrufen (`welcomePage.continue.fetch`: fetch im Hintergrund, 5 s, ohne Rückfrage nach Zugangsdaten), Reiter „Gemerkt“ mit Notizen, Lesezeichen und Favoriten aller Projekte (`welcomePage.saved`), Bereich „Projekte“ mit Zustand je Projekt (`welcomePage.projectStatus`), höchstens so viele Projekte (`welcomePage.maxProjects`, 1–30), Branch und Änderungen frisch abfragen (`welcomePage.refreshVcs`), Bereich „Projektverlauf“ mit einer Linie je Reihe über die letzten Builds des in „Projekte“ gewählten (sonst obersten) Projekts, letzter Wert, Vorwert, Lücke für unbekannte Werte, Klick auf einen Punkt zeigt Build, Datum, Branch und Commit; Klick auf eine Projektzeile wählt sie dann, Doppelklick öffnet (`welcomePage.trends`; aus = kein Bereich, keine neuen Messpunkte, Klick öffnet wieder), gespeicherte und gezeigte Builds je Projekt (`welcomePage.trends.points`, 2–100), gezeigte Reihen (`welcomePage.trends.series`: Liste aus warnings, ruleHits, todos, duration, methodLength), Bereich „Nicht gesichert“ mit nicht Committetem, nicht Gepushtem und Stashes je Projekt (`welcomePage.unsaved`), erst ab so vielen Stunden zeigen (`welcomePage.unsaved.minAgeHours`, 0–8760), gelb ab (`welcomePage.unsaved.warnHours`, 0–8760), rot ab (`welcomePage.unsaved.alertHours`, 0–8760, nie unter warnHours), Bereich ausblenden, wenn alles gesichert ist (`welcomePage.unsaved.hideWhenClean`; sonst Zeile „Alles gesichert“), Zustandskachel „Atlas“ mit Server, Version, Index, Einrichtung und Diagnosemodus (`welcomePage.statusTile`), Kachel nur bei einer gelben oder roten Zeile (`welcomePage.statusTile.onlyProblems`), Karte „Atlas entdecken“ mit einem Tipp je Start aus `tips.json` der Installation, Bild, tatsächlichem Kürzel und „Noch nie benutzt“/„Zuletzt vor 3 Wochen“, Knöpfe „Ausprobieren“, „Nächster Tipp“, „Nicht mehr zeigen“ (`welcomePage.discover`; zuerst eingeschaltete, nie benutzte Funktionen, dann lange nicht benutzte; abgeschaltete nie), Nutzung je Befehl lokal zählen (`tips.usageTracking`; aus = Tipps der Reihe nach, es wird nichts gezählt), Knöpfe „Zählung zurücksetzen“ und „Gesperrte Tipps wieder zeigen“, Bereich „Hilfe und Rückmeldung“ mit „Atlas-Doku“ (lokale HTML-Doku `Doku\index.html` der Installation, sonst die Doku-Seite des Repositorys), „Tastenkürzel“ (Übersicht aus #520, ausgegraut mit `keys.overview` aus) und „Problem melden …“ (Dialog: Kurzbeschreibung, Häkchen für Logs, Versionen, Einstellungen ohne Pfade und letzte Diagnosedaten, Vorschau jeder Datei, „ZIP anlegen“ schreibt `Atlas-Diagnose-<Datum>.zip` und zeigt sie im Explorer, „Issue-Seite öffnen“ legt die Vorlage in die Zwischenablage und öffnet die Seite im Browser; Atlas sendet nichts) (`welcomePage.help`), Ziel für „Issue-Seite öffnen“ (`welcomePage.help.reportUrl`, nur http:// oder https://, sonst die Vorgabe), Ordner für das Diagnosepaket (`welcomePage.help.reportFolder`, leer = Desktop), Karte „<Projekt> für Atlas einrichten“ für das aktive bzw. zuletzt geöffnete Projekt mit den Schritten atlas.json anlegen (Vorlage „Bestehendes Projekt“, „Neues Projekt, streng“ oder „Altprojekt mit Baseline“ aus dem Ordner `Vorlagen` der Installation, vorher gegen das Schema geprüft und gezeigt), Baseline erzeugen (#97) und Suchpfade und Defines prüfen (fehlende Units aus uses, Defines ohne Quelle; Klick öffnet die Projektoptionen), jeder Schritt nur auf Klick, „Für dieses Projekt nicht mehr fragen“ dauerhaft, *Atlas.ProjectSetup* in der Palette fragt wieder (`welcomePage.projectSetup`, Schnellschalter; aus = keine Karte, keine Knöpfe, kein Befehl), Knöpfe „Neu mit Atlas“ (Unit, Formular, Testklasse) öffnen das Erzeugen-Menü mit den Dateivorlagen und legen die Datei im aktuellen Projekt an (`welcomePage.newFromTemplate`) | an, welcomePage, off, an, an, an, an, Strg+E, afterUpdate, an, 5, an, aus, an, an, 8, an, an, 30, alle fünf, an, 0, 24, 72, aus, an, aus, an, an, an, Issue-Seite des Atlas-Repositorys, Desktop, an, an | Plugin (Registry `WelcomePage`, `WelcomePageHost`, `WelcomePageLayout`, `WelcomePageHeader`, `WelcomePageGreeting`, `WelcomePageSearch`, `WelcomePageSearchSymbols`, `WelcomePageSearchKey`, `WelcomePageWhatsNew`, `WelcomePageContinue`, `WelcomePageContinueCount`, `WelcomePageContinueIncoming`, `WelcomePageContinueFetch`, `WelcomePageSaved`, `WelcomePageProjectStatus`, `WelcomePageMaxProjects`, `WelcomePageRefreshVcs`, `WelcomePageTrends`, `WelcomePageTrendsPoints`, `WelcomePageTrendsSeries`, `WelcomePageUnsaved`, `WelcomePageUnsavedMinAgeHours`, `WelcomePageUnsavedWarnHours`, `WelcomePageUnsavedAlertHours`, `WelcomePageUnsavedHideWhenClean`, `WelcomePageStatusTile`, `WelcomePageStatusTileOnlyProblems`, `WelcomePageDiscover`, `TipsUsageTracking`, `WelcomePageHelp`, `WelcomePageHelpReportUrl`, `WelcomePageHelpReportFolder`, `WelcomePageProjectSetup`, `WelcomePageNewFromTemplate`; gesehene Version in `WhatsNewSeen`); Zählung je Befehl (nur Kennung, Zähler, Datum, nichts wird versendet) in `%LOCALAPPDATA%\Atlas\usage.json`, gesperrte und zuletzt gezeigter Tipp im Abschnitt `discover` von `%LOCALAPPDATA%\Atlas\shortcut-tips.json`; Sicherung in `%LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json`, Projektzustand (auch Abschnitte `unsaved`, `continue`, `trends` und `setup`) in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json`, letzter Index-Stand der Kachel („Stand vom …“) in `%LOCALAPPDATA%\Atlas\index-state.json` | nein | Kontrollkästchen, Auswahl, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Tastenfeld, Auswahl, Kontrollkästchen, Zahl (1–20), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Zahl (1–30), Kontrollkästchen, Kontrollkästchen, Zahl (2–100), fünf Kontrollkästchen, Kontrollkästchen, Zahl (0–8760), Zahl (0–8760), Zahl (0–8760), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Knopf, Knopf, Kontrollkästchen, Textfeld, Textfeld mit „…“, Kontrollkästchen, Kontrollkästchen | #753, #760, #756, #755, #592, #758, #762, #754, #757, #766, #759 |')
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
