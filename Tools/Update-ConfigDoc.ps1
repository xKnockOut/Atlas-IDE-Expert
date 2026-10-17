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
      x-scope ("global" = %APPDATA%\Atlas\settings.json, "project" = atlas.json,
      "both" = an beiden Orten, das Projekt übersteuert je Glied; steht in beiden Listen).
      Jeder Schlüssel der obersten Ebene braucht x-scope; ein Glied darf mit
      eigenem x-scope abweichen (gemischtes Objekt wie index, completion).

    - schemas/atlas-plugin.schema.json: Katalog der Plugin-Einstellungen mit
      x-key, x-area, x-page (#723). Wächter: genau die Namen aus
      TAtlasPluginSettings.Save, Bereiche aus x-areas, x-key eindeutig. Jeder
      globale Schlüssel in atlas.schema.json braucht x-area. Daraus entstehen
      Atlas.Core.Settings.PluginSchemaData, der Abschnitt „Bereiche für Export,
      Import und Zurücksetzen“ in Einstellungen.md und aus Setup/Profile/*.json
      die Unit Atlas.Core.Settings.ProfileData (eingebaute Profile).

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
$PluginSchemaPath = Join-Path $Root 'schemas/atlas-plugin.schema.json'
$PluginSchema = Get-Content -Raw -Encoding utf8 $PluginSchemaPath | ConvertFrom-Json -AsHashtable
$PluginPath = Join-Path $Root 'Packages/Atlas.IDE.Expert/Source/Core/Settings/Atlas.Core.Settings.Plugin.pas'
$ProfileFolder = Join-Path $Root 'Setup/Profile'

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
    if ($Scope -eq 'both') { return 'global und Projekt' }
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
[void]$Out.AppendLine('Jeder Schlüssel hat genau einen Ort (Spalte „Ort“): Projekt-Schlüssel stehen in `atlas.json` im Projektordner (im Plugin *Atlas › Projekt-Einstellungen*), globale in `%APPDATA%\Atlas\settings.json` für alle Projekte (im Plugin *Tools › Optionen › Atlas*). Ausnahme `rules`: Prüfregeln gehen an beiden Orten, global für alle Projekte, `atlas.json` übersteuert je Regel. Ein Schlüssel am falschen Ort wird ignoriert und als Warnung gemeldet. Fehlende Schlüssel nehmen den Standardwert. In der IDE bestimmt die laufende IDE die Delphi-Version (`delphiVersion` gilt dort nicht). Die Prüfregeln stehen in [Regeln.md](Regeln.md).')
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
    $Source = if ($Scope -eq 'global') { 'settings.json (Tools › Optionen › Atlas)' } elseif ($Scope -eq 'both') { 'settings.json (Tools › Optionen › Atlas) und atlas.json (Atlas › Projekt-Einstellungen)' } else { 'atlas.json (Atlas › Projekt-Einstellungen)' }
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
[void]$Table.AppendLine('| Compiler | Beim Öffnen einmal bauen (`build.onOpen`, Schnellschalter; Art `build.onOpenKind`: `check` Syntaxprüfung, `make` Compilieren, `build` Erzeugen): Wird ein Projekt oder eine Projektgruppe geöffnet (auch das beim Start der IDE geladene), baut Atlas es einmal über den Compiler der IDE, sobald die IDE ruhig ist (keine Eingabe seit `build.onOpenDelayMs`, kein Build, kein Debugger, keine Compilerprüfung); mit eingeschalteter Hintergrundcompilierung der IDE ohne zu blockieren, sonst mit ihrem Fortschrittsdialog. Einmal je Öffnen; Tests nach dem Build laufen nicht, der Release-Wächter prüft wie bei jedem Build. Ergebnis je Projekt in der Benachrichtigungszentrale, bei mehreren Projekten zusätzlich eine Zusammenfassung (Quelle `openBuild`); aus = kein Bau beim Öffnen | aus, make | Plugin (Registry `BuildOnOpen`, `BuildOnOpenKind`) | nein | Auswahl „nicht bauen / Syntaxprüfung / Compilieren / Erzeugen“ |  |')
[void]$Table.AppendLine('| Compiler | Umfang in einer Projektgruppe (`build.onOpenScope`: `all` alle Projekte in der Reihenfolge der Gruppe, `active` nur das aktive Projekt) | all | Plugin (Registry `BuildOnOpenScope`) | nein | Auswahl |  |')
[void]$Table.AppendLine('| Compiler | Wartezeit beim Öffnen (`build.onOpenDelayMs`, 500 bis 60000 ms): so lange nach dem letzten Öffnen und nach der letzten Eingabe, bevor Atlas baut | 3000 | Plugin (Registry `BuildOnOpenDelayMs`) | nein | Zahl |  |')
[void]$Table.AppendLine('| Compiler | Beim Öffnen nicht bauen (`build.onOpenExclude`, Projektnamen ohne Endung, durch Komma getrennt), z. B. ein in dieser IDE installiertes Package | – | Plugin (Registry `BuildOnOpenExclude`) | nein | Textfeld |  |')
[void]$Table.AppendLine('| Release-Build | Release-Build-Wächter (`build.releaseGuard`, Schnellschalter): vor make und build in einer Release-Konfiguration prüft Atlas die Projektoptionen, wie die laufende IDE sie für den Build verwendet (mit geerbten Werten, auch ungespeichert; nicht die .dproj auf der Platte), nach `build.releaseChecks`. Verstöße stehen in der Atlas-Gruppe des Meldungsfensters mit Regel-ID und Hinweis, wo die Option zu ändern ist. Gilt auch für Builds über den Läufer (Claude Code `build_project`, „Öffnen und bauen“ #764), nie für Debug-Konfigurationen, die Hintergrundprüfung, Syntaxprüfung, Clean oder Code Insight. Befehl „Release-Build prüfen“ (*Atlas.CheckRelease*, Befehlspalette) prüft das aktive Projekt ohne Build. Ergebnis und Version jedes erfolgreichen Release-Builds stehen im Abschnitt `release` der Projekt-Zusammenfassung; aus = keine Prüfung und kein Befehl | an | Plugin (Registry `ReleaseGuard`) | nein | Kontrollkästchen | #533 |')
[void]$Table.AppendLine('| Release-Build | Bei Befunden (`build.gate`: off, warn, block; Vorgriff auf #529): off und warn melden nur, block bricht den Build ab (der Läufer meldet dann „nicht gebaut“ mit Grund); ein zweiter Build mit denselben Befunden binnen 10 s läuft trotzdem (bewusst übergehen) | off | Plugin (Registry `BuildGate`) | nein | Auswahl | #529, #533 |')
[void]$Table.AppendLine('| Release-Build | Release-Konfigurationen (`build.releaseConfigs`, durch Komma getrennt; „Release“ gilt immer, Groß-/Kleinschreibung egal) | Release | Plugin (Registry `ReleaseConfigs`) | nein | Textfeld | #533 |')
[void]$Table.AppendLine('| Release-Build | Prüfungen des Wächters (`build.releaseChecks`, durch Komma getrennt; `-name` schaltet eine ab): `debugDefine` (Symbol DEBUG), `debugInfo` (Debug-Informationen; mit Sollwert aus auch „Mit Debug-Informationen linken“), `stackFrames`, `assertions`, `rangeChecks`, `overflowChecks` (je mit Sollwert `=off` oder `=on`; fehlt die Option, gilt die Vorgabe des Compilers), `memoryLeaks` (`ReportMemoryLeaksOnShutdown := True` im Projektquelltext außerhalb von `{$IFDEF DEBUG}`), `versionInfo` (keine Versionsinformationen oder dieselbe Version wie beim letzten erfolgreichen Release-Build derselben Konfiguration und Plattform; nicht mit automatisch erhöhter Build-Nummer), `outputFolder` (Ausgabeordner gleich dem der Konfiguration Debug). Packages ohne `memoryLeaks` und `outputFolder`. Regel-IDs `release-debug-define` bis `release-output-folder` | alle an, Sollwerte aus | Plugin (Registry `ReleaseChecks`) | nein | Kontrollkästchen bzw. Auswahl je Prüfung | #533 |')
[void]$Table.AppendLine('| Debuggen | Einzelnen Test debuggen (#585, `tests.debug`, Schnellschalter): Befehle „Test am Cursor debuggen“ (*Atlas.DebugTest*) und „Test am Cursor ausführen“ (*Atlas.RunTest*, mit `tests.run`) in der Befehlspalette, Einträge „Test debuggen“/„Test ausführen“ im Kontextmenü des Editors und Marke „Debuggen“ der Code Lens an `[TestFixture]`, `[Test]` und je `[TestCase]`; Atlas baut das Testprojekt (wie „Tests ausführen“), setzt über die Startprofile (#575) vorübergehend die Startparameter `--run:<Unit.Fixture.Methode[.Fall]>` (vorhandene Parameter bleiben, `--run`, `--include`, `--exclude`, `--xmlfile` und `--exitbehavior` weichen) und startet es im Debugger; danach gelten aktives Projekt und Startparameter wie vorher (auch nach einem Absturz beim nächsten Start), das Ergebnis erscheint wie bei „Tests ausführen“. Braucht „Tests ausführen“; aus = Befehl, Eintrag, Marke und Tipp verschwinden | an | Plugin (Registry `TestDebug`) | nein | Kontrollkästchen | #585 |')
[void]$Table.AppendLine('| Debuggen | Beim Test-Debuggen am Anfang der Methode anhalten (`debug.testBreakAtStart`): einmaliger Haltepunkt auf der ersten Anweisung der Testmethode, den Atlas nach dem ersten Halt wieder entfernt (ein eigener Haltepunkt dort bleibt unberührt); nicht beim Debuggen einer ganzen Fixture | an | Plugin (Registry `TestBreakAtStart`) | nein | Kontrollkästchen | #585 |')
[void]$Table.AppendLine('| Baseline | `atlas-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |')
[void]$Table.AppendLine('| Projektdatei | Projektdatei `.atlas` (#486) lesen (`teamFile.enabled`, Schnellschalter): Einstellungen des Plugins für alle im Team, im Ordner der .dproj, sonst in der Wurzel des Repositorys (nächster Ordner mit `.git`); JSON mit Kommentaren und `version` (1) mit `naming` (Präfixe `field`, `parameter`, `local`, #452), `snippets` (Ordner mit Projekt-Vorlagen, #51), `formatFunctions` (`name`, `formatIndex`, #451), `sqlTargets` (#462), `fileMethods` (#478), `mainThreadExceptions` (#484), `startProfiles` (`name`, `parameters`, `workingDir`, `host`, `environment`, #575), `ci` (`provider` jenkins, `url`, `job`, `multibranch`, #763) `tracker` (`provider` github oder youtrack, `url`, `project`, #765) und `hidden` (am Element ausgeblendete Stellen: `setting` = Schlüssel der Einstellung des Elements, `file` relativ zur `.atlas`, `anchor` = Methode, Zeilentext o. Ä., ohne `anchor` gilt es für die ganze Datei; schreibt „Nur hier/In dieser Datei ausblenden“, #628). Werte aus `.atlas` haben Vorrang vor den persönlichen (Listen ergänzen sich), der Reiter *Projektdatei* zeigt jeden mit „aus .atlas“. Zugangsdaten, absolute Pfade und Pfade außerhalb des Repositorys werden ignoriert (ein Startprofil damit ganz), fehlerhafte Dateien und ignorierte Einträge in der Meldungsansicht gemeldet; dann gelten die persönlichen Einstellungen. Befehl *Projektdatei .atlas öffnen* (*Atlas.TeamFile*, Befehlspalette, Knopf auf dem Reiter) legt die Datei mit Gerüst an und öffnet sie | an | Plugin (Registry `TeamFile`); Datei `.atlas` im Repository | nein | Kontrollkästchen, Werte „aus .atlas“, Knopf „Projektdatei öffnen“ | #486 |')
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
[void]$Table.AppendLine('| Allgemein | Verhalten je Quelle (`notifications.sources`): `quelle=verhalten`, kommagetrennt; Quellen build, check, reload, server, buildServer (Build-Server rot geworden, #763), shortcutTips, openBuild (Zusammenfassung „Beim Öffnen gebaut“, `build.onOpen`), hidden (Hinweis „Ausgeblendet · Rückgängig“ und Ablehnungen beim Ausblenden am Element, #628); Verhalten show = einblenden und sammeln, collect = nur sammeln (keine eigene Einblendung bzw. keine Zeile im Meldungsfenster), off = weder noch; auch im Kontextmenü eines Eintrags; „Build fertig“ hat noch keine eigene Einblendung (#535), dort wirken show und collect gleich | leer (alle show) | Plugin (Registry `NotificationsSources`) | nein | Auswahl (Quelle, Verhalten) | #601, #763, #628 |')
[void]$Table.AppendLine('| Allgemein | Höchstzahl der Einträge in der Liste der Benachrichtigungen (`notifications.maxEntries`, 10–1000); ältere fallen weg | 200 | Plugin (Registry `NotificationsMaxEntries`) | nein | Zahl | #601 |')
[void]$Table.AppendLine('| Allgemein | Abgesicherter Start nach einem Absturz: Rückfrage (`safeMode.askAfterCrash`), ohne Rückfrage nach zwei Abstürzen (`safeMode.autoAfterRepeatedCrash`), Taste beim Laden (`safeMode.startupKey`: shift, ctrl, none), längste Ladezeit (`safeMode.startupTimeoutMs`), gemerkte Einstellungsstände (`safeMode.keepSettingsHistory`) | an, an, shift, 10000, 5 | Plugin (Registry `SafeAskAfterCrash`, `SafeAutoAfterRepeatedCrash`, `SafeStartupKey`, `SafeStartupTimeoutMs`, `SafeKeepSettingsHistory`); Kommandozeile `-AtlasSafeMode`, Umgebungsvariable `ATLAS_SAFE_MODE=1` | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Zahl (1000–120000), Zahl (0–50) | #722 |')
[void]$Table.AppendLine('| Allgemein | Atlas-Änderungen über mehrere Dateien zurücknehmen: an/aus (`undo.multiFile`), Anzahl Sätze (`undo.multiFile.depth`), über Neustarts sichern (`undo.multiFile.persist`) bis höchstens MB (`undo.multiFile.maxSizeMb`), bei Konflikten (`undo.multiFile.onConflict`: partial, abort), neu angelegte Dateien (`undo.multiFile.newFiles`: recycleBin, delete, keep), Tasten Zurücknehmen und Wiederherstellen | an, 20, an, 50, partial, recycleBin, Strg+Alt+Z, Strg+Alt+Umschalt+Z | Plugin (Registry `UndoMultiFile`, `UndoMultiFileDepth`, `UndoMultiFilePersist`, `UndoMultiFileMaxSizeMb`, `UndoMultiFileOnConflict`, `UndoMultiFileNewFiles`, `UndoKey`, `RedoKey`); Sicherung in `%LOCALAPPDATA%\Atlas\undo` | nein | Kontrollkästchen, Zahl (1–200), Kontrollkästchen, Zahl (1–1024), Auswahl, Auswahl, Tastenkürzel, Tastenkürzel | #721 |')
[void]$Table.AppendLine('| Allgemein | Nach Zustimmung beim ersten Start höchstens einmal täglich auf eine neue Atlas-Version prüfen (`updates.check`); übertragen werden nur Atlas- und IDE-Version, ein Hinweis erscheint in der Meldungsansicht und als gelbe Zeile „Version“ im Statusfeld und in der Zustandskachel | aus | Plugin (Registry `UpdatesCheck`); Zustand (auch die gefundene neue Version) in `%LOCALAPPDATA%\Atlas\updates.json` | nein | Kontrollkästchen | #495 |')
[void]$Table.AppendLine('| Allgemein | Fehlerbericht (*Atlas › Fehlerbericht erstellen…*) anonymisieren: Pfade unter dem Projekt zu `<ws>`, andere Pfade zu `<pfad>`, Benutzername und Bezeichner im Protokoll ersetzen (`diagnostics.bugReport.anonymize`) | an | Plugin (Registry `BugReportAnonymize`) | nein | Kontrollkästchen | #108 |')
[void]$Table.AppendLine('| Allgemein | Einstellungen exportieren, importieren und zurücksetzen (`settings.exportImport`, Schnellschalter): Knöpfe unten auf *Tools › Optionen › Atlas* und Befehle *Atlas.SettingsExport*, *Atlas.SettingsImport*, *Atlas.SettingsProfile*, *Atlas.SettingsReset* (Befehlspalette) sowie `AtlasSetup.exe /exportSettings`, `/importSettings`, `/resetSettings`; geänderte Werte mit Punkt am Feld (`settings.markModified`), Sicherung in `%APPDATA%\Atlas\Backups` vor jedem Import (`settings.backupBeforeImport`), Zugangsdaten auslassen oder als Platzhalter (`settings.exportSecrets`: omit, placeholder); Bereiche siehe unten | an, an, an, omit | Plugin (Registry `SettingsExportImport`, `SettingsMarkModified`, `SettingsBackupBeforeImport`, `SettingsExportSecrets`) | nein | Kontrollkästchen, Auswahl, Knöpfe „Exportieren…“, „Importieren…“, „Profil laden…“, „Seite zurücksetzen“, „Alles zurücksetzen…“, Kontextmenü „Auf Standard zurücksetzen“ | #723 |')
[void]$Table.AppendLine('| Vervollständigung | Favoriten anheften (`completion.favorites`, Schnellschalter): Strg+D in der offenen Liste oder Klick auf den Stern, der beim Überfahren einer Zeile erscheint, heftet den Eintrag an bzw. löst ihn; angeheftete Einträge stehen mit Stern links vor allen anderen Gruppen, unabhängig von Lernen und Rangfolge, aber nur, wenn sie zum getippten Präfix passen; je Paar (Typ, Member) wie die lernende Gewichtung, höchstens 5 je Typ (ein sechster ersetzt nichts, die Fußzeile nennt den Grund); Liste mit „Entfernen“ und „Alle entfernen“ auf der Optionsseite | an | Plugin (Registry `Favorites`); Favoriten in `%APPDATA%\Atlas\favorites.json` (Typ, Member, Art, Unit, Signatur, Zeitpunkt; lesbar ohne Server) | nein | Kontrollkästchen, Liste mit Knöpfen | #458 |')
[void]$Table.AppendLine('| Editor | Zwischen Unit und Testunit wechseln: Code Lens über der Zeile `unit …;` (`codeLens.testUnit`) und Tastenkürzel (Befehl auch im Atlas-Menü, Kontextmenü und in der Befehlspalette) | an, keins | Plugin (Registry `CodeLensTestUnit`, `TestUnitKey`) | nein | Kontrollkästchen, Tastenkürzel | #189 |')
[void]$Table.AppendLine('| Editor | Code Lens „Test ausführen“ (`codeLens.tests`, Schnellschalter; gemeinsamer Schlüssel mit „Test debuggen“ #585): hinter `[TestFixture]` und `[Test]`/`[TestCase]` (bzw. der Deklaration registrierter Fixtures und published-Methoden) eine Marke mit dem Ergebnis des letzten Laufs (bestanden grün, fehlgeschlagen rot, während eines Laufs „Tests laufen …“); Klick startet den Test bzw. alle Tests der Fixture; ein `[TestCase]` in eigener Zeile hat eine eigene Marke „Fall ausführen“ (#585); daneben „Debuggen“, wenn „Test debuggen“ an ist. Braucht „Tests ausführen“; aus = keine Marken, weder „Test ausführen“ noch „Debuggen“ | an | Plugin (Registry `CodeLensTests`) | nein | Kontrollkästchen | #69 |')
[void]$Table.AppendLine('| Editor | Code-Metriken (#66): Code Lens hinter dem Kopf jeder implementierten Methode mit Länge, Verschachtelungstiefe, zyklomatischer und kognitiver Komplexität und Parameteranzahl, Werte über dem Grenzwert markiert (`codeLens.metrics`, Schnellschalter; Grenzwerte als `max` der Regeln `metric-*` in atlas.json); Befehl „Metrikbericht des Projekts“ (*Atlas.MetricsReport*, Befehlspalette, abschaltbar mit `metrics.report`, Schnellschalter; aus = der Befehl verschwindet) schreibt den Markdown-Bericht des aktiven Projekts nach `%LOCALAPPDATA%\Atlas\Berichte\Metriken-<Projekt>.md` und öffnet ihn; nach jedem Build (nicht nach einer Hintergrundprüfung) legt das Plugin die Zusammenfassung im Abschnitt `metrics` der Projekt-Zusammenfassung ab (Projektverlauf #758) | an, an | Plugin (Registry `CodeLensMetrics`, umgeleitet nach settings.json `codeLens.metrics`; Registry `MetricsReport`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen, Kontrollkästchen | #66 |')
[void]$Table.AppendLine('| Editor | TODO-Übersicht (#68): Befehle „TODOs des Projekts“ (*Atlas.TodoList*) und „TODOs des Projekts filtern …“ (*Atlas.TodoListFilter*, Kategorie, Person, Unit, Marke, Erledigte) in der Befehlspalette (`todos.list`, Schnellschalter; aus = beide Befehle verschwinden) listen die offenen `// TODO`, `// FIXME` und `{ TODO … }` des aktiven Projekts nach Unit im Ergebnisfenster; Marken als `keywords` der Regel `todo-comment` in atlas.json (Vorgabe `TODO`, `FIXME`), Hinweise im Editor nur mit eingeschalteter Regel; nach jedem Build legt das Plugin die Zählung im Abschnitt `todos` der Projekt-Zusammenfassung ab (Projektverlauf #758) | an, Hinweise aus | Plugin (Registry `TodoList`); Server (atlas.json `rules.todo-comment`: Schweregrad und `keywords`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen; Regel und Marken nur in atlas.json | #68 |')
[void]$Table.AppendLine('| Editor | Baseline für Altprojekte (#97): Befehl „Baseline des Projekts aktualisieren“ (*Atlas.UpdateBaseline*, Befehlspalette, abschaltbar mit `baseline.update`, Schnellschalter; aus = der Befehl verschwindet, die Baseline wirkt weiter) lässt den Server (`atlas.updateBaseline`) alle Dateien des aktiven Projekts prüfen und `atlas-baseline.json` im Arbeitsbereich neu schreiben; vorher nennt er Einträge, deren Datei es nicht mehr gibt, und fragt nach, danach stehen die Zähler (neu, entfernt, unverändert) im Meldungsfenster; nach jedem Build und nach dem Aktualisieren legt das Plugin den Stand der Baseline im Abschnitt `baseline` der Projekt-Zusammenfassung ab (Projektverlauf #758, Einrichtung #759) | an | Plugin (Registry `BaselineUpdate`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen | #97 |')
[void]$Table.AppendLine('| Editor | Eigenschaftsregeln für Formulare (#309): Befehle „Eigenschaftsregeln anwenden: Formular“, „…: Projekt“ und „…: Projektgruppe“ (*Atlas.ApplyDfmRulesForm*, *Atlas.ApplyDfmRulesProject*, *Atlas.ApplyDfmRulesGroup*, Befehlspalette, abschaltbar mit `dfmPropertyRules.apply`, Schnellschalter; aus = die Befehle verschwinden, Regel `dfm-property` und Schnellkorrektur bleiben) lassen den Server (`atlas.server.applyDfmPropertyRules`) die Korrekturen aller Regeln aus `dfmPropertyRules` in den Formulardateien sammeln; eine Vorschau zeigt jede geänderte Zeile vorher und nachher, erst „Anwenden“ übernimmt sie (offene Formulare im Designer, die übrigen auf der Platte) | an | Plugin (Registry `DfmPropertyRules`) | nein | Kontrollkästchen | #309 |')
[void]$Table.AppendLine('| Editor | Persönliche Notizen an Codezeilen (`notes.enabled`, Schnellschalter): *Atlas › Notiz an dieser Zeile…* (Befehlspalette, Atlas-Untermenü im Editor-Kontextmenü; nach Rechtsklick in die Rinne für die angeklickte Zeile) legt eine ein- oder mehrzeilige Notiz an, ein Symbol in der Rinne zeigt sie, Überfahren zeigt den Text; *Atlas › Notizen des Projekts* listet alle im Ergebnisfenster (Datei, Zeile, Text, Doppelklick springt, verwaiste Notizen gesondert); die Notiz folgt ihrer Zeile über Inhalt und je zwei Nachbarzeilen | an | Plugin (Registry `Notes`); Notizen je Projekt in `%LOCALAPPDATA%\Atlas\Notes\<Schlüssel>.json`, nie im Repository | nein | Kontrollkästchen | #545 |')
[void]$Table.AppendLine('| Editor | Benannte Lesezeichen (`bookmarks.named`, Schnellschalter): *Atlas › Lesezeichen setzen…* (Strg+Alt+K, Befehlspalette, Atlas-Untermenü im Editor-Kontextmenü; nach Rechtsklick in die Rinne für die angeklickte Zeile) fragt nach dem Namen und schlägt Methode und Zeilenbeginn vor; ein Band in der Rinne zeigt das Lesezeichen, Überfahren zeigt den Namen; *Atlas › Gehe zu Lesezeichen…* sucht unscharf über Name, Datei und Methode; das Seitenfenster *Atlas › Lesezeichen-Fenster* listet Name, Datei, Methode und Zeilenvorschau mit Filter (Klick oder Enter springt, F2 benennt um, Entf löscht, Ziehen sortiert); das Lesezeichen sucht zuerst seine Methode und dann den Zeilentext darin, fehlt beides, steht es als „nicht gefunden“ in der Liste; aus: alles ruht, die IDE-Lesezeichen bleiben unberührt | an | Plugin (Registry `BookmarksNamed`) | nein | Kontrollkästchen | #622 |')
[void]$Table.AppendLine('| Editor | Lesezeichen im Repository für das Team (`bookmarks.shared`): `atlas-bookmarks.json` neben der .dproj zum Einchecken statt der persönlichen `.atlas-bookmarks.json` (die Atlas lokal in `.git/info/exclude` einträgt); gibt es die Team-Datei noch nicht, gelten zunächst die persönlichen Lesezeichen | aus | Plugin (Registry `BookmarksShared`) | nein | Kontrollkästchen | #622 |')
[void]$Table.AppendLine('| Editor | Tastenkürzel für „Lesezeichen setzen…“ (`bookmarks.key`, Reiter *Befehle*; leer = keins) | Strg+Alt+K | Plugin (Registry `BookmarkKey`) | nein | Tastenkürzel | #622 |')
[void]$Table.AppendLine('| Editor | Beschriftung hinter dem `end` langer Blöcke (`editor.blockEndLabels`, Schnellschalter): „// TKunde.Speichern“ bzw. „// if Kunde.Aktiv“ als leiser Text hinter dem `end` von Methoden und Blöcken ab einer Länge, die der Server meldet (Inlay-Hints vom Server, #401); läuft auch bei ausgeschalteten Inlay-Hints | an | Plugin (Registry `BlockEndLabels`) | nein | Kontrollkästchen | #620, #628 |')
[void]$Table.AppendLine('| Editor | Ausblenden direkt am Element (#628): Rechtsklick auf Code Lens, Blockende-Beschriftung oder Inlay-Hint, für Unterstreichungen, Randsymbole (Notizen, Lesezeichen), Klammerfarben, Blocklinien, Abblendungen und die Vorschau der Vervollständigung der Eintrag „Element ausblenden …“ im Editor-Kontextmenü (gilt für die Stelle des Rechtsklicks) oder Strg+. (an der Cursorzeile) bietet „Nur hier ausblenden“ (bei Befunden mit Regel ein Unterdrückungskommentar `// lsp-ignore: <Regel>` über der Zeile, #147; sonst ein Eintrag im Abschnitt `hidden` der Projektdatei `.atlas`), „In dieser Datei ausblenden“ (`// lsp-ignore-file: <Regel>` am Dateianfang bzw. Eintrag ohne `anchor`; Elemente, die nur ganze Dateien kennen, bieten nur diesen und „überall“), „… überall ausblenden“ (schaltet die Einstellung des Elements aus, alle verschwinden sofort) und „Einstellungen dazu …“ (öffnet *Tools › Optionen › Atlas* mit der Zeile hervorgehoben); danach kurz „Ausgeblendet · Rückgängig“ (Benachrichtigungsquelle `hidden`); Befehl *Atlas.HideElement* in der Befehlspalette; Taste (`keys.hideElement`, Reiter *Befehle*; leer = keins; Vorrang wie die Editorbefehle, sonst bleibt Strg+. bei der IDE) | Strg+. | Plugin (Registry `HideElementKey`); „Nur hier“ und „In dieser Datei“ ohne Regel in `.atlas` (braucht `teamFile.enabled`) | nein | Tastenkürzel | #628 |')
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
[void]$Table.AppendLine('| Willkommensseite | Atlas-Bereiche auf der Willkommensseite (`welcomePage.enabled`, Schnellschalter), anzeigen in (`welcomePage.host`: welcomePage, dockWindow = Fenster „Atlas-Start“), Atlas-Layout (`welcomePage.layout`: off, atlas; mit Sicherung des bisherigen Layouts, *Atlas › Atlas-Layout anwenden/zurücksetzen*), Kopf mit Symbol und Version (`welcomePage.header`), Grußzeile (`welcomePage.greeting`), Suchfeld im Kopf (`welcomePage.search`), Gruppe „Symbole“ darin (`welcomePage.search.symbols`, braucht laufenden Server), Taste für das Suchfeld (`welcomePage.search.key`, nur auf der Willkommensseite), Karte „Neu in Atlas“ (`welcomePage.whatsNew`: off = nie, afterUpdate = einmalig nach einem Update, always = immer), Bereich „Weiterarbeiten“ mit den letzten Arbeitsständen (Reiter, zuletzt bearbeitete Datei und Methode, „Fortsetzen“ öffnet Projekt und Reiter und setzt den Cursor an die letzte Änderung; *Atlas.Continue* in der Palette) (`welcomePage.continue`; aus = kein Bereich, nichts wird mitgeschrieben), höchstens so viele Arbeitsstände (`welcomePage.continue.count`, 1–20), „Neu seit deinem letzten Öffnen“ mit eingehenden Commits zu den eigenen Dateien aus dem lokalen Stand der Remote-Branches (`welcomePage.continue.incoming`), vorher abrufen (`welcomePage.continue.fetch`: fetch im Hintergrund, 5 s, ohne Rückfrage nach Zugangsdaten), Reiter „Gemerkt“ mit Notizen, Lesezeichen und Favoriten aller Projekte (`welcomePage.saved`), Bereich „Projekte“ mit Zustand je Projekt (`welcomePage.projectStatus`), höchstens so viele Projekte (`welcomePage.maxProjects`, 1–30), Branch und Änderungen frisch abfragen (`welcomePage.refreshVcs`), Bereich „Projektverlauf“ mit einer Linie je Reihe über die letzten Builds des in „Projekte“ gewählten (sonst obersten) Projekts, letzter Wert, Vorwert, Lücke für unbekannte Werte, Klick auf einen Punkt zeigt Build, Datum, Branch und Commit; Klick auf eine Projektzeile wählt sie dann, Doppelklick öffnet (`welcomePage.trends`; aus = kein Bereich, keine neuen Messpunkte, Klick öffnet wieder), gespeicherte und gezeigte Builds je Projekt (`welcomePage.trends.points`, 2–100), gezeigte Reihen (`welcomePage.trends.series`: Liste aus warnings, ruleHits, todos, duration, methodLength), Bereich „Nicht gesichert“ mit nicht Committetem, nicht Gepushtem und Stashes je Projekt (`welcomePage.unsaved`), erst ab so vielen Stunden zeigen (`welcomePage.unsaved.minAgeHours`, 0–8760), gelb ab (`welcomePage.unsaved.warnHours`, 0–8760), rot ab (`welcomePage.unsaved.alertHours`, 0–8760, nie unter warnHours), Bereich ausblenden, wenn alles gesichert ist (`welcomePage.unsaved.hideWhenClean`; sonst Zeile „Alles gesichert“), Zustandskachel „Atlas“ mit Server, Version, Index, Einrichtung und Diagnosemodus (`welcomePage.statusTile`), Kachel nur bei einer gelben oder roten Zeile (`welcomePage.statusTile.onlyProblems`), Karte „Atlas entdecken“ mit einem Tipp je Start aus `tips.json` der Installation, Bild, tatsächlichem Kürzel und „Noch nie benutzt“/„Zuletzt vor 3 Wochen“, Knöpfe „Ausprobieren“, „Nächster Tipp“, „Nicht mehr zeigen“ (`welcomePage.discover`; zuerst eingeschaltete, nie benutzte Funktionen, dann lange nicht benutzte; abgeschaltete nie), Nutzung je Befehl lokal zählen (`tips.usageTracking`; aus = Tipps der Reihe nach, es wird nichts gezählt), Knöpfe „Zählung zurücksetzen“ und „Gesperrte Tipps wieder zeigen“, Bereich „Hilfe und Rückmeldung“ mit „Atlas-Doku“ (lokale HTML-Doku `Doku\index.html` der Installation, sonst die Doku-Seite des Repositorys), „Tastenkürzel“ (Übersicht aus #520, ausgegraut mit `keys.overview` aus) und „Problem melden …“ (Dialog: Kurzbeschreibung, Häkchen für Logs, Versionen, Einstellungen ohne Pfade und letzte Diagnosedaten, Vorschau jeder Datei, „ZIP anlegen“ schreibt `Atlas-Diagnose-<Datum>.zip` und zeigt sie im Explorer, „Issue-Seite öffnen“ legt die Vorlage in die Zwischenablage und öffnet die Seite im Browser; Atlas sendet nichts) (`welcomePage.help`), Ziel für „Issue-Seite öffnen“ (`welcomePage.help.reportUrl`, nur http:// oder https://, sonst die Vorgabe), Ordner für das Diagnosepaket (`welcomePage.help.reportFolder`, leer = Desktop), Karte „<Projekt> für Atlas einrichten“ für das aktive bzw. zuletzt geöffnete Projekt mit den Schritten atlas.json anlegen (Vorlage „Bestehendes Projekt“, „Neues Projekt, streng“ oder „Altprojekt mit Baseline“ aus dem Ordner `Vorlagen` der Installation, vorher gegen das Schema geprüft und gezeigt), Baseline erzeugen (#97) und Suchpfade und Defines prüfen (fehlende Units aus uses, Defines ohne Quelle; Klick öffnet die Projektoptionen), jeder Schritt nur auf Klick, „Für dieses Projekt nicht mehr fragen“ dauerhaft, *Atlas.ProjectSetup* in der Palette fragt wieder (`welcomePage.projectSetup`, Schnellschalter; aus = keine Karte, keine Knöpfe, kein Befehl), Knöpfe „Neu mit Atlas“ (Unit, Formular, Testklasse) öffnen das Erzeugen-Menü mit den Dateivorlagen und legen die Datei im aktuellen Projekt an (`welcomePage.newFromTemplate`), Bereich „Testergebnisse“ mit einer Zeile je Projekt aus dem letzten DUnitX-Lauf in der IDE (#69: Ampel, Marke „2 fehlgeschlagen“ bzw. „alle 57 ok“, bestanden, übersprungen, Dauer, Zeit), darunter die fehlgeschlagenen Tests des gewählten Projekts mit Meldung und Datei:Zeile, Doppelklick öffnet Projekt und Test, „Fehlgeschlagene erneut ausführen“ startet genau diese Tests, „Im Debugger“ den gewählten (#585) (`welcomePage.tests`), höchstens so viele Fehlschläge (`welcomePage.tests.maxFailures`, 1–50), Ergebnisse vom Build-Server (`welcomePage.tests.ci`; Server, Job und Multibranch aus dem Abschnitt `ci` der `.atlas`, bei Multibranch der Job des aktuellen Branches; REST `…/lastCompletedBuild/api/json` und `…/testReport/api/json`; zweite Zeile „Jenkins #482 · 2 fehlgeschlagen · vor 40 Min. · main“, Server-Fehlschläge in derselben Liste mit Marke „Server“, „lokal grün, Server rot“ hervorgehoben, „Im Browser“ öffnet die Seite des Builds; abgefragt beim Anzeigen im Hintergrund mit 5 s Zeitgrenze; nicht erreichbar = letzter Stand mit „Stand vom …“, kein Dialog; aus = kein Netzzugriff, `.atlas` wird dafür nicht gelesen), Anbieter, wenn die `.atlas` keinen nennt (`welcomePage.tests.ci.provider`: jenkins), höchstens alle so viele Minuten je Job (`welcomePage.tests.ci.intervalMinutes`, 1–1440, auch nach einem Fehler und über einen Neustart hinweg), Hinweis in der Benachrichtigungszentrale, wenn ein neuer Build rot wird (`welcomePage.tests.ci.notify`, Quelle `buildServer`, mit „Im Browser“), Befehl „Zugang zum Build-Server hinterlegen …“ (*Atlas.CiLogin*, Schnellschalter; auch im Kontextmenü des Bereichs): Benutzer und API-Token für den Server aus der `.atlas` des aktiven Projekts im Anmeldespeicher von Windows (Ziel `Atlas:ci:<Server>`), das Token verdeckt eingegeben, beide Felder leer entfernt den Zugang; angemeldet wird nur über https und nur beim eingetragenen Server, Weiterleitungen nur auf denselben Rechner; Adresse, Job, Benutzer und Token kommen nie ins Protokoll, Schnellaktionen je Projekt in „Projekte“ und „Weiterarbeiten“: Knöpfe in der Zeile unter der Maus bzw. der Tastatur „Öffnen und bauen ▾“ (öffnet Projekt bzw. Gruppe wie die IDE und baut mit der zuletzt benutzten oder gewählten Konfiguration und Plattform, Release-Wächter #533 gilt), „Tests“ (baut das zugehörige DUnitX-Testprojekt und führt es aus, #69; Ergebnis auch in „Testergebnisse“), „Startprofil ▾“ (#575), „Pull“ bzw. bei SVN „Aktualisieren“ (nur vorwärts, gesperrt bei lokalen Änderungen: „Erst lokale Änderungen sichern“), „Ordner“ (Explorer) und „Konsole“; Fortschritt „baut … 12 s“ in der Zeile, Ergebnis als Marke; ohne Maus über Pfeiltasten, Enter, Alt+↓ und Kontextmenütaste (`welcomePage.quickActions`, Schnellschalter; aus = keine Knöpfe, die Tasten bleiben bei der IDE), gezeigte Knöpfe (`welcomePage.quickActions.items`: Liste aus build, tests, run, pull, folder, console), Programm für „Konsole“ im Projektordner (`welcomePage.quickActions.console`; ohne Windows-Terminal cmd.exe), Taste für „Öffnen und bauen“ (`welcomePage.quickActions.buildKey`) und für „Tests“ (`welcomePage.quickActions.testKey`), beide nur in einer Zeile mit Fokus, Bereich „Meine Issues · <Projekt>“ mit den mir zugewiesenen offenen Issues aus dem Tracker der `.atlas` des in „Projekte“ gewählten, sonst des aktiven Projekts (Abschnitt `tracker`; GitHub: Vorgabe-Abfrage `assignee:@me state:open`, Kennung `#123`, Labels und verknüpfter Pull Request mit CI-Ampel; YouTrack: Vorgabe `for: me #Unresolved`, Kennung `ATL-123`, Zustand, Priorität und Sprint), Klick auf die Kennung öffnet das Issue im Browser, abgefragt beim Anzeigen höchstens alle 10 Minuten im Hintergrund mit 5 s Zeitgrenze, nicht erreichbar = letzter Stand mit „Stand vom …“, kein Dialog; „Beginnen“ legt unter Git den Branch nach Muster von der Basis an und checkt ihn aus (vorhandener Branch: nur auschecken; bei lokalen Änderungen fragt Atlas vorher), unter SVN `svn copy ^/trunk ^/branches/<Name>` und `svn switch`, und öffnet danach das Projekt; das aktuelle Issue steht im Atlas-Statusfeld (Zeile `atlas.issue`, Klick beendet es nach Rückfrage) (`welcomePage.issues`, Schnellschalter; aus = kein Bereich, kein Netzzugriff), Anbieter (`welcomePage.issues.tracker`: leer = aus der `.atlas`, github, youtrack), Abfrage (`welcomePage.issues.query`, leer = Vorgabe des Anbieters), „Beginnen“ (`welcomePage.issues.start`: branch, remember = nur Kennung merken), Branch-Muster (`welcomePage.issues.branchPattern` mit `{kennung}`, `{nummer}` und `{kurztitel}` = erste drei Wörter, klein, Umlaute ersetzt, mit Bindestrichen; leer = `feature/{kennung}-{kurztitel}`, unter SVN `{kennung}-{kurztitel}`), Basis (`welcomePage.issues.branchBase`, leer = main, sonst master; SVN trunk), Präfix für Commit-Nachrichten, solange ein Issue aktuell ist (`welcomePage.issues.commitPattern`, leer = aus; im Commit-Dialog der IDE und nach einmaliger Zustimmung je Projekt über den Git-Hook `prepare-commit-msg`, der den Präfix aus `.git/atlas-commit-prefix` liest; einen fremden Hook ändert Atlas nie), Befehl „Zugang zum Issue-Tracker hinterlegen …“ (*Atlas.TrackerLogin*, Schnellschalter; auch im Kontextmenü des Bereichs): Token für den Tracker aus der `.atlas` des aktiven Projekts im Anmeldespeicher von Windows (Ziel `Atlas:tracker:<Server>`), verdeckt eingegeben, leer entfernt es; gesendet als „Authorization: Bearer“ nur über https an den Tracker; Adresse, Projekt, Kennungen, Titel und Token kommen nie ins Protokoll, frei anordnen mit „Seite anpassen“ (Leiste unter dem Kopf, Kontextmenü der Bereiche, *Atlas.WelcomeCustomize* in der Palette): Griff zum Ziehen und Strg+Pfeiltasten, Breite und Auge je Bereich, „Bereich hinzufügen“, „Zurücksetzen“, Leiste „Ausgeblendet“, benannte Layouts mit Umschalter im Kopf; Ausblenden schaltet die Einstellung des Bereichs (`welcomePage.customLayout`, Schnellschalter; aus = kein Bearbeitungsmodus, festes Atlas-Layout), Spalten der Seite (`welcomePage.columns`, 1–3), aktives Layout (`welcomePage.activeLayout`, leer = Standard), Layouts mit Plätzen, Breiten, Spalten und Sichtbarkeit (`welcomePage.layouts`, JSON, leer = ein Layout „Standard“ wie das Atlas-Layout) | an, welcomePage, off, an, an, an, an, Strg+E, afterUpdate, an, 5, an, aus, an, an, 8, an, an, 30, alle fünf, an, 0, 24, 72, aus, an, aus, an, an, an, Issue-Seite des Atlas-Repositorys, Desktop, an, an, an, 5, aus, jenkins, 10, an, an, an, alle sechs, wt.exe, Strg+B, Strg+T, aus, leer, leer, branch, leer, leer, `{kennung} `, an, an, 2, Standard, leer | Plugin (Registry `WelcomePage`, `WelcomePageHost`, `WelcomePageLayout`, `WelcomePageHeader`, `WelcomePageGreeting`, `WelcomePageSearch`, `WelcomePageSearchSymbols`, `WelcomePageSearchKey`, `WelcomePageWhatsNew`, `WelcomePageContinue`, `WelcomePageContinueCount`, `WelcomePageContinueIncoming`, `WelcomePageContinueFetch`, `WelcomePageSaved`, `WelcomePageProjectStatus`, `WelcomePageMaxProjects`, `WelcomePageRefreshVcs`, `WelcomePageTrends`, `WelcomePageTrendsPoints`, `WelcomePageTrendsSeries`, `WelcomePageUnsaved`, `WelcomePageUnsavedMinAgeHours`, `WelcomePageUnsavedWarnHours`, `WelcomePageUnsavedAlertHours`, `WelcomePageUnsavedHideWhenClean`, `WelcomePageStatusTile`, `WelcomePageStatusTileOnlyProblems`, `WelcomePageDiscover`, `TipsUsageTracking`, `WelcomePageHelp`, `WelcomePageHelpReportUrl`, `WelcomePageHelpReportFolder`, `WelcomePageProjectSetup`, `WelcomePageNewFromTemplate`, `WelcomePageTests`, `WelcomePageTestsMaxFailures`, `WelcomePageTestsCi`, `WelcomePageTestsCiProvider`, `WelcomePageTestsCiIntervalMinutes`, `WelcomePageTestsCiNotify`, `CiLogin`, `WelcomePageQuickActions`, `WelcomePageQuickActionsItems`, `WelcomePageQuickActionsConsole`, `WelcomePageQuickActionsBuildKey`, `WelcomePageQuickActionsTestKey`, `WelcomePageIssues`, `WelcomePageIssuesTracker`, `WelcomePageIssuesQuery`, `WelcomePageIssuesStart`, `WelcomePageIssuesBranchPattern`, `WelcomePageIssuesBranchBase`, `WelcomePageIssuesCommitPattern`, `TrackerLogin`, `WelcomePageCustomLayout`, `WelcomePageColumns`, `WelcomePageActiveLayout`, `WelcomePageLayouts`; gesehene Version in `WhatsNewSeen`); Zählung je Befehl (nur Kennung, Zähler, Datum, nichts wird versendet) in `%LOCALAPPDATA%\Atlas\usage.json`, gesperrte und zuletzt gezeigter Tipp im Abschnitt `discover` von `%LOCALAPPDATA%\Atlas\shortcut-tips.json`; Sicherung in `%LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json`, Projektzustand (auch Abschnitte `unsaved`, `continue`, `trends`, `setup`, `tests`, `ci` und `issues`, die beiden letzten mit letztem Stand, Zeit des letzten Versuchs und Fehlerart, ohne Zugang; `issues` auch mit aktuellem Issue und Zustimmung zum Git-Hook) in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json`, letzter Index-Stand der Kachel („Stand vom …“) in `%LOCALAPPDATA%\Atlas\index-state.json` | nein | Kontrollkästchen, Auswahl, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Tastenfeld, Auswahl, Kontrollkästchen, Zahl (1–20), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Zahl (1–30), Kontrollkästchen, Kontrollkästchen, Zahl (2–100), fünf Kontrollkästchen, Kontrollkästchen, Zahl (0–8760), Zahl (0–8760), Zahl (0–8760), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Knopf, Knopf, Kontrollkästchen, Textfeld, Textfeld mit „…“, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Zahl (1–50), Kontrollkästchen, Auswahl, Zahl (1–1440), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, sechs Kontrollkästchen, Textfeld, Tastenfeld, Tastenfeld, Kontrollkästchen, Auswahl, Textfeld, Auswahl, Textfeld, Textfeld, Textfeld, Kontrollkästchen, Kontrollkästchen, Zahl (1–3), Auswahl mit „Neu …“, „Umbenennen …“ und „Löschen“, Bearbeitungsmodus der Seite | #753, #760, #756, #755, #592, #758, #762, #754, #757, #766, #759, #763, #764, #765, #767 |')

# --- Bereiche für Export, Import und Zurücksetzen (#723) ---
$AreaKeys = [ordered]@{}
foreach ($Area in $PluginSchema['x-areas'].PSBase.Keys) { $AreaKeys[$Area] = New-Object System.Collections.Generic.List[string] }
$Skipped = New-Object System.Collections.Generic.List[string]
$PluginKeys = @{}
foreach ($Name in $PluginSchema['properties'].Keys) {
    $P = $PluginSchema['properties'][$Name]
    if (-not (Has $P 'x-key')) { continue }
    $PluginKeys[$P['x-key']] = $Name
    if (((Has $P 'x-state') -and $P['x-state']) -or ((Has $P 'x-machine') -and $P['x-machine'])) { $Skipped.Add('`' + $P['x-key'] + '`'); continue }
    if ((Has $P 'x-area') -and $AreaKeys.Contains($P['x-area'])) { $AreaKeys[$P['x-area']].Add('`' + $P['x-key'] + '`') }
}
foreach ($Name in $Schema['properties'].Keys) {
    if ($Name -eq '$schema') { continue }
    $P = $Schema['properties'][$Name]
    $Scope = Scope-Of $P ''
    $Leaves = @()
    if (Has $P 'properties') {
        foreach ($Sub in $P['properties'].Keys) {
            $S = $P['properties'][$Sub]
            if ('global', 'both' -cnotcontains (Scope-Of $S $Scope)) { continue }
            $Area = if (Has $S 'x-area') { $S['x-area'] } elseif (Has $P 'x-area') { $P['x-area'] } else { '' }
            $Leaves += , @("$Name.$Sub", $Area, ((Has $S 'x-machine') -or (Has $P 'x-machine')))
        }
    }
    elseif ('global', 'both' -ccontains $Scope) {
        $Area = if (Has $P 'x-area') { $P['x-area'] } else { '' }
        $Leaves += , @($Name, $Area, (Has $P 'x-machine'))
    }
    foreach ($Leaf in $Leaves) {
        if ($PluginKeys.ContainsKey($Leaf[0])) { continue }
        if ($Leaf[2]) { $Skipped.Add('`' + $Leaf[0] + '`'); continue }
        if ($AreaKeys.Contains($Leaf[1])) { $AreaKeys[$Leaf[1]].Add('`' + $Leaf[0] + '`') }
    }
}
[void]$Table.AppendLine()
[void]$Table.AppendLine('## Bereiche für Export, Import und Zurücksetzen')
[void]$Table.AppendLine()
[void]$Table.AppendLine('*Tools › Optionen › Atlas*, die Befehlspalette und `AtlasSetup.exe` exportieren, importieren und setzen Einstellungen je Bereich zurück (#723, abschaltbar mit `settings.exportImport`). Den Bereich bestimmt `x-area` im Schema: je Plugin-Einstellung im Katalog `schemas/atlas-plugin.schema.json`, je globalem Schlüssel in `atlas.schema.json`. Neue Einstellungen gehören damit ohne weitere Liste dazu. Die Exportdatei `atlas-settings.json` enthält nur geänderte Werte, keine Zugangsdaten (`settings.exportSecrets`: auslassen oder Platzhalter) und keine Pfade mit Benutzernamen (Benutzerordner werden zu `$(APPDATA)`, `$(LOCALAPPDATA)`, `$(USERPROFILE)`). Projekt- und Teamwerte (`atlas.json`, `.atlas`) werden weder exportiert noch beim Import überschrieben.')
[void]$Table.AppendLine()
[void]$Table.AppendLine('| Bereich | Schlüssel |')
[void]$Table.AppendLine('|---|---|')
foreach ($Area in $AreaKeys.PSBase.Keys) {
    [void]$Table.AppendLine("| $($PluginSchema['x-areas'][$Area]['caption']) (``$Area``) | $($AreaKeys[$Area] -join ', ') |")
}
[void]$Table.AppendLine("| nicht exportiert (Zustand, nur dieser Rechner) | $($Skipped -join ', ') |")
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
    if ((Has $P 'x-scope') -and ('global', 'project', 'both' -cnotcontains $P['x-scope'])) { $Problems.Add("Schema: ""$Name"" mit x-scope ""$($P['x-scope'])""; erlaubt sind global, project und both") }
    if (Has $P 'properties') {
        foreach ($Sub in $P['properties'].Keys) {
            $S = $P['properties'][$Sub]
            if ((Has $S 'x-scope') -and ('global', 'project' -cnotcontains $S['x-scope'])) { $Problems.Add("Schema: ""$Name.$Sub"" mit x-scope ""$($S['x-scope'])""; erlaubt sind global und project") }
        }
    }
}

# --- Wächter: Katalog der Plugin-Einstellungen (#723) ---
$PluginText = [IO.File]::ReadAllText($PluginPath, $Utf8)
$SaveNames = @([regex]::Matches($PluginText, "Write(?:Integer|String)\('(\w+)'") | ForEach-Object { $_.Groups[1].Value })
$CatalogNames = @($PluginSchema['properties'].Keys)
foreach ($Name in $SaveNames) { if ($CatalogNames -cnotcontains $Name) { $Problems.Add("Plugin-Katalog: ""$Name"" aus TAtlasPluginSettings.Save fehlt in schemas/atlas-plugin.schema.json") } }
foreach ($Name in $CatalogNames) { if ($SaveNames -cnotcontains $Name) { $Problems.Add("Plugin-Katalog: ""$Name"" wird in TAtlasPluginSettings.Save nicht geschrieben") } }
$SeenKeys = @{}
foreach ($Name in $CatalogNames) {
    $P = $PluginSchema['properties'][$Name]
    foreach ($Meta in 'type', 'default', 'x-key', 'x-area', 'x-page') {
        if (-not $P.ContainsKey($Meta)) { $Problems.Add("Plugin-Katalog: ""$Name"" ohne $Meta") }
    }
    if ((Has $P 'x-area') -and -not $PluginSchema['x-areas'].Contains($P['x-area'])) { $Problems.Add("Plugin-Katalog: ""$Name"" mit unbekanntem Bereich ""$($P['x-area'])""") }
    if (Has $P 'x-key') {
        if ($SeenKeys.ContainsKey($P['x-key'])) { $Problems.Add("Plugin-Katalog: x-key ""$($P['x-key'])"" doppelt ($($SeenKeys[$P['x-key']]), $Name)") }
        else { $SeenKeys[$P['x-key']] = $Name }
    }
}
foreach ($Name in $Schema['properties'].Keys) {
    if ($Name -eq '$schema') { continue }
    $P = $Schema['properties'][$Name]
    $Scope = Scope-Of $P ''
    if (('global', 'both' -ccontains $Scope) -and -not (Has $P 'x-area')) { $Problems.Add("Schema: globaler Schlüssel ""$Name"" ohne x-area (Bereich für Export und Import, #723)") }
    if ((Has $P 'x-area') -and -not $PluginSchema['x-areas'].Contains($P['x-area'])) { $Problems.Add("Schema: ""$Name"" mit unbekanntem Bereich ""$($P['x-area'])""") }
    if (Has $P 'properties') {
        foreach ($Sub in $P['properties'].Keys) {
            $S = $P['properties'][$Sub]
            if (('global', 'both' -ccontains (Scope-Of $S $Scope)) -and -not (Has $S 'x-area') -and -not (Has $P 'x-area')) { $Problems.Add("Schema: globaler Schlüssel ""$Name.$Sub"" ohne x-area") }
            if ((Has $S 'x-area') -and -not $PluginSchema['x-areas'].Contains($S['x-area'])) { $Problems.Add("Schema: ""$Name.$Sub"" mit unbekanntem Bereich ""$($S['x-area'])""") }
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
# --- Pascal-Units mit eingebettetem JSON: UTF-8 mit BOM, CRLF ---
function Pascal-Lines([string] $Name, [string] $Source) {
    $Lines = $Source.TrimStart([char]0xFEFF).Replace("`r`n", "`n").TrimEnd("`n").Split("`n")
    $Result = @("  $Name`: array[0..$($Lines.Count - 1)] of string = (")
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        $Escaped = $Lines[$Index].Replace("'", "''")
        $Pieces = @()
        for ($At = 0; $At -lt $Escaped.Length; $At += 200) { $Pieces += "'" + $Escaped.Substring($At, [Math]::Min(200, $Escaped.Length - $At)) + "'" }
        if ($Pieces.Count -eq 0) { $Pieces = @("''") }
        $End = if ($Index -eq $Lines.Count - 1) { ');' } else { ',' }
        $Result += '    ' + ($Pieces -join ' + ') + $End
    }
    return $Result
}
function Sync-Unit([string] $Path, [string[]] $Lines) {
    $Text = ($Lines -join "`r`n") + "`r`n"
    $Current = if (Test-Path $Path) { [IO.File]::ReadAllText($Path, $Utf8).TrimStart([char]0xFEFF) } else { '' }
    if ($Current -eq $Text) { return }
    if ($Check) { $Problems.Add("$(Split-Path -Leaf $Path) ist veraltet: pwsh Tools/Update-ConfigDoc.ps1 ausführen") }
    else {
        [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "Geschrieben: $Path"
    }
}
function Text-Unit([string] $UnitName, [string[]] $Comment, [string] $Summary, [string] $FunctionName, [string] $Source) {
    return @("unit $UnitName;", '') + $Comment + @('', 'interface', '', "/// <summary>$Summary</summary>", "function $FunctionName`: string;", '',
        'implementation', '', 'const') + (Pascal-Lines 'Lines' $Source) +
        @('', "function $FunctionName`: string;", 'var', '  Line: string;', 'begin', "  Result := '';",
        '  for Line in Lines do', '    Result := Result + Line + #10;', 'end;', '', 'end.')
}
$SettingsFolder = Join-Path $Root 'Packages/Atlas.IDE.Expert/Source/Core/Settings'

# Schema für den Einstellungsdialog im Plugin (#227)
Sync-Unit (Join-Path $SettingsFolder 'Atlas.Core.Settings.SchemaData.pas') (Text-Unit 'Atlas.Core.Settings.SchemaData' @(
    '// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json;',
    '// nicht von Hand ändern. JSON-Schema von atlas.json für den Einstellungsdialog (#227).') `
    'Inhalt von atlas.schema.json.' 'AtlasSchemaJson' ([IO.File]::ReadAllText($SchemaPath, $Utf8)))

# Katalog der Plugin-Einstellungen (#604, #723)
Sync-Unit (Join-Path $SettingsFolder 'Atlas.Core.Settings.PluginSchemaData.pas') (Text-Unit 'Atlas.Core.Settings.PluginSchemaData' @(
    '// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas-plugin.schema.json;',
    '// nicht von Hand ändern. Katalog der Plugin-Einstellungen: Schnellschalter (#604),',
    '// Bereiche für Export, Import und Zurücksetzen (#723).') `
    'Inhalt von atlas-plugin.schema.json.' 'AtlasPluginSchemaJson' ([IO.File]::ReadAllText($PluginSchemaPath, $Utf8)))

# Eingebaute Profile (#723) aus Setup/Profile/*.json
$Profiles = @(Get-ChildItem -Path $ProfileFolder -Filter '*.json' -File | Sort-Object Name)
if ($Profiles.Count -eq 0) { $Problems.Add('Setup/Profile: keine Profile gefunden') }
$ProfileLines = @('unit Atlas.Core.Settings.ProfileData;', '',
    '// Erzeugt von Tools/Update-ConfigDoc.ps1 aus Setup/Profile/*.json;',
    '// nicht von Hand ändern. Eingebaute Profile für den Import der Einstellungen (#723).', '',
    'interface', '',
    '/// <summary>Dateinamen der eingebauten Profile (wie in Setup\Profile).</summary>',
    'function AtlasProfileFiles: TArray<string>;',
    '/// <summary>Inhalt eines eingebauten Profils; leer, wenn der Name unbekannt ist.</summary>',
    'function AtlasProfileJson(const AFileName: string): string;', '',
    'implementation', '', 'uses', '  System.SysUtils;', '', 'const')
for ($Index = 0; $Index -lt $Profiles.Count; $Index++) {
    $ProfileLines += Pascal-Lines "Profile$Index" ([IO.File]::ReadAllText($Profiles[$Index].FullName, $Utf8))
}
$ProfileLines += @('', 'function Joined(const ALines: array of string): string;', 'var', '  Line: string;', 'begin', "  Result := '';",
    '  for Line in ALines do', '    Result := Result + Line + #10;', 'end;', '',
    'function AtlasProfileFiles: TArray<string>;', 'begin', "  SetLength(Result, $($Profiles.Count));")
for ($Index = 0; $Index -lt $Profiles.Count; $Index++) { $ProfileLines += "  Result[$Index] := '$($Profiles[$Index].Name)';" }
$ProfileLines += @('end;', '', 'function AtlasProfileJson(const AFileName: string): string;', 'begin', "  Result := '';")
for ($Index = 0; $Index -lt $Profiles.Count; $Index++) {
    $ProfileLines += "  if SameText(AFileName, '$($Profiles[$Index].Name)') then"
    $ProfileLines += "    Result := Joined(Profile$Index);"
}
$ProfileLines += @('end;', '', 'end.')
Sync-Unit (Join-Path $SettingsFolder 'Atlas.Core.Settings.ProfileData.pas') $ProfileLines

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
    elseif ($Scope -eq 'both') { $GlobalPaths.Add($Name); $ProjectPaths.Add($Name) }
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
    '// Projekt = atlas.json. Gemischte Objekte stehen je Glied als "objekt.glied" da.',
    '// Schlüssel mit x-scope "both" stehen in beiden Listen.', '',
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
Write-Host 'Schema, Plugin-Katalog, Parser, erzeugte Units und Doku stimmen überein.'
exit 0
