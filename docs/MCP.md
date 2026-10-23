# MCP-Modus

Mit `--mcp` bietet Atlas den Symbolindex eines Projektordners über das
Model Context Protocol an (stdio, eine JSON-Nachricht je Zeile). Ein KI-Assistent
kann damit Fragen zum Projekt beantworten, ohne Quelldateien vollständig zu lesen.

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

`--root` ist der Ordner mit `atlas.json` bzw. der .dproj; ohne Angabe das
aktuelle Verzeichnis. `--log <Datei>` schreibt ein Protokoll, stdout gehört allein
dem Protokoll.

Liegt in `--root` genau eine `.groupproj`, indiziert der Server zusätzlich alle
übrigen Projekte der Gruppe in denselben Index (`index.projectGroup`, Standard an).
So findet er auch Units, die nur ein anderes Projekt der Gruppe enthält, wenn
`project` in `atlas.json` auf ein einzelnes Projekt zeigt.

Pfadparameter (#99): relativ zu `--root` oder absolut; sie werden normalisiert
(`..`, Junctions, Symlinks, subst-Laufwerke aufgelöst) und nur im Arbeitsordner
sowie in den Such- und Bibliothekspfaden des Projekts angenommen. Alles andere
ergibt einen Werkzeugfehler mit Begründung. Geschrieben wird nur im Arbeitsordner.

## Sicherheit (#99)

- Jedes Werkzeug ist lesend, schreibend oder startet einen Prozess.
- `mcp.disabledTools` in `atlas.json` schaltet Werkzeuge einzeln ab, z. B.
  `"mcp": { "disabledTools": ["rename_symbol", "apply_code_action"] }`. Abgeschaltete
  Werkzeuge fehlen in `tools/list`; ein Aufruf ergibt einen Werkzeugfehler mit Begründung.
- Mit `--restricted` (#186) sind nur lesende Werkzeuge verfügbar.
- Wie der LSP-Server liest der MCP-Server auch die globale Datei `%APPDATA%\Atlas\settings.json`
  (dort steht `mcp.disabledTools` normalerweise, ebenso Index- und Hint-Einstellungen). Mit
  `"mcp": { "globalSettings": false }` in `atlas.json` gilt nur die Projektdatei (D-08).
- Schreibende Werkzeuge haben `dryRun` mit Vorgabe `true`: Sie liefern dann nur den Diff.
  Mit `dryRun: false` schreiben sie atomar: Hat sich eine Datei seit dem Lesen geändert
  oder ist sie in der IDE ungespeichert geändert (das IDE-Plugin meldet das in
  `%LOCALAPPDATA%\Atlas\editor-dirty-<pid>.json`), wird nichts geschrieben; scheitert das Schreiben
  einer Datei, werden die schon geschriebenen zurückgesetzt. Kodierung und Zeilenenden
  bleiben erhalten (#121).
- Ist eine Datei in einer IDE mit Atlas-Plugin offen, schreibt der MCP-Server sie nicht selbst (#397):
  Er legt die Änderung in den Eingang des Plugins (`%LOCALAPPDATA%\Atlas\ide-edits\<pid>\`), das sie
  als einen Rückgängig-Schritt in den Puffer übernimmt und die Datei speichert. Die Änderung erscheint
  sofort im Editor. Nimmt das Plugin den Auftrag nicht binnen 3 s an, schreibt der MCP-Server wie bisher
  selbst; das Neuladen der IDE holt die Datei dann nach.
- Jeder schreibende Aufruf steht mit Werkzeug, Parametern und geänderten Dateien im Log
  (`--log`).

## Ressourcen

| URI | Inhalt |
|---|---|
| `delphi://conventions` | Projektkonventionen als Markdown (#272): Regelprofil, Formatstil, Benennungsregeln und jede aktive Prüfregel mit Schweregrad und Kurztext aus dem Regelkatalog. Vor dem Schreiben lesen, danach mit `check_code` prüfen |

## Werkzeuge

| Werkzeug | Parameter | Ergebnis |
|---|---|---|
| `find_symbol` | `name` | Fundstellen mit Art, Typ, Unit, Datei:Zeile; ohne exakten Treffer Teilstring-Suche |
| `get_declaration` | `name` | Quelltext der Deklaration, auch aus RTL/VCL |
| `get_type_hierarchy` | `name` | Vorfahren bis zur Wurzel, Nachfahren rekursiv |
| `get_component_info` | `name` | published-Properties mit Typ und Default (ausdrücklich, implizit, `nodefault`, `stored`), Ereignisse mit Signatur, Vorfahrenkette, Palettenseite aus `RegisterComponents`, Package aus `contains` der .dpk; ohne Quellen ein Hinweis statt leerer Liste |
| `get_unit_outline` | `unit` | uses-Listen und Symbole einer Unit mit Zeilennummern |
| `find_references` | `name` | Verwendungen im Projekt mit Datei:Zeile und Quelltextzeile |
| `get_call_hierarchy` | `name`, `direction` | Aufrufer (`incoming`) und Aufgerufene (`outgoing`), Standard beides |
| `qualified_name` | `file`, `line`, `column`, `withParameters` (optional) | Voll qualifizierter Name des Symbols an der Stelle, z. B. `Vcl.Controls.TControl.Paint`; mit `withParameters` bei Routinen samt Parametertypen |
| `get_diagnostics` | `file` (optional) | Syntaxfehler und Regelbefunde einer Datei oder aller Projektdateien |
| `get_metrics` | `file` (optional), `format` (`markdown` oder `json`) | Code-Metriken je Methode (#66): Länge in Codezeilen, Verschachtelungstiefe, zyklomatische und kognitive Komplexität, Parameteranzahl; Bericht mit den Methoden über einem Grenzwert aus `atlas.json` (Regeln `metric-*`, Option `max`) oder die Metrikdaten als JSON |
| `get_todos` | `file`, `unit`, `category`, `owner`, `keyword`, `includeDone` (alle optional), `format` (`markdown` oder `json`) | TODO-Übersicht (#68) aller Dateien, die das Projektmodell dem Projekt zuordnet: `// TODO`, `// FIXME` und das Format der IDE-To-Do-Liste `{ TODO 1 -oPerson -cKategorie : Text }` mit Priorität, Person und Kategorie, gefiltert nach Unit, Kategorie, Person oder Marke; erledigte Einträge (`{ DONE … }`) nur mit `includeDone`. Weitere Marken über die Option `keywords` der Regel `todo-comment`. Markdown mit Zählung nach Kategorie und Person und je Unit einer Tabelle, oder JSON (`format` 1, Zeilen ab 1) |
| `get_architecture` | `section` (`overview`, `central`, `subsystems`, `cycles`, `crossLinks`; Vorgabe `overview`), `unit` (optional) | Architekturübersicht (#1118) aus dem uses-Graphen: Teilsysteme (Louvain-Gruppen eng verbundener Units) mit Namen, zentrale Units, Zyklen und Querverbindungen zwischen Teilsystemen, je mit Datei:Zeile der uses-Einträge; mit `unit` der Steckbrief einer Unit. Umfang (`architecture.scope`), Bibliotheks-Units und Ausschlüsse aus `atlas.json`; dieselben Zahlen wie das Fenster „Atlas-Architektur“ und `--architecture`. Mit `architecture.enabled` = false nicht angeboten |
| `check_code` | `file`, `text`, `startLine`/`endLine` (optional) | Prüft geplanten Code ohne zu schreiben: Syntaxfehler, Regelbefunde, nicht auflösbare Bezeichner. Ohne Bereich ist `text` die ganze Unit, sonst der Ersatz für die Zeilen `startLine`..`endLine` |
| `get_dfm_info` | `file` | Komponentenbaum eines Text-Formulars mit Eigenschaften und Ereignissen |
| `get_last_build` | `project` (optional) | Letzter Build, den der Benutzer in der IDE gestartet hat (über das IDE-Plugin, #556): Ergebnis, Art, Zeitpunkt, Dauer, Projekt, Konfiguration, Plattform, Zahl der Fehler/Warnungen/Hinweise und alle Meldungen mit Datei, Zeile, Spalte (1-basiert), Code und Text; Meldungen außerhalb von `--root` bleiben weg. Ohne Build: „Noch kein Build …“. Austausch über `%LOCALAPPDATA%\Atlas\build-*.json`, die der LSP-Server schreibt |
| `build_project` | `project`, `mode` (`make`, `build`, `check`; Vorgabe `make`), `configuration`, `platform` (alle optional) | Startet einen Prozess (#261): baut ein Projekt in der laufenden RAD-Studio-IDE über das Atlas-Plugin (IOTAProjectBuilder), auch ohne Kommandozeilen-Compiler (Starter Edition), und liefert das Ergebnis wie `get_last_build`. Das Projekt muss in einer IDE mit Atlas-Plugin offen sein; ohne `project` das aktive Projekt, wenn es unter `--root` liegt. Konfiguration und Plattform gelten nur für diesen Build. Austausch über `%LOCALAPPDATA%\Atlas\ide-builds\<pid>\`; nimmt das Plugin den Auftrag nicht binnen 5 s an (abgeschaltet über „Builds für Claude Code“, Debugger oder anderer Build aktiv), meldet das Werkzeug den Grund |
| `run_tests` | `project`, `tests` (Liste aus `Unit.Fixture` oder `Unit.Fixture.Methode`), `build` (Vorgabe `false`), `configuration`, `platform`, `timeoutSeconds` (Vorgabe 600, höchstens 3600; alle optional) | Startet einen Prozess (#69): führt die DUnitX-Tests eines Testprojekts aus. Testprojekt ist ein `.dproj` unter `--root`, dessen Hauptdatei `DUnitX.TestFramework` verwendet; ohne `project` das einzige solche. Die Plattform kommt aus dem Projekt (Vorgabe der Datei, sonst die erste aktivierte; ein Projekt nur für Win64 läuft als Win64), die Test-EXE aus `DCC_ExeOutput` und der Hauptdatei. Eine vorhandene EXE läuft ohne Compiler; mit `build: true` baut es vorher in der laufenden IDE wie `build_project` (ohne IDE mit Atlas-Plugin meldet es den Grund, schlägt der Build fehl, laufen keine Tests). Aufruf mit `--exitbehavior:Continue --xmlfile:<temp> [--run:…]`; das Testprogramm braucht den XML-Logger von DUnitX (`TDUnitXXMLNUnitFileLogger`, wie in der Vorlage von RAD Studio), sonst `result: noReport` mit den letzten Zeilen der Ausgabe. Ergebnis als JSON: `result` (`passed`, `failed`, `noTests`, `noReport`), Projekt, Konfiguration, Plattform, EXE, Exit-Code, Zahlen (`total`, `passed`, `failed`, `errors`, `skipped`, `durationMs`) und je fehlgeschlagenem Test (höchstens 100) Name, Meldung, `expected`/`actual` (aus „Expected … but got …“), Datei und Zeile (1-basiert) des Methodenkopfs. Läufe über MCP stehen nicht in der Projekt-Zusammenfassung der Willkommensseite; das tun nur Läufe aus der IDE |
| `explain_finding` | `file`, `line`, `rule` (optional) | Befunde einer Zeile als Markdown (#158): Regel mit Beschreibung, Codeausschnitt mit markierter Zeile, Vorher/Nachher-Beispiel aus dem Regelkatalog. |
| `rename_symbol` | `file`, `line`, `column`, `newName`, `dryRun` (Vorgabe `true`) | Schreibend (#61): benennt das Symbol an der Stelle projektweit um, samt `.dfm`/`.fmx` und automatisch benannter Ereignis-Handler; liefert den Diff aller Dateien |
| `apply_code_action` | `file`, `line`, `title` (optional), `dryRun` (Vorgabe `true`) | Schreibend (#61): ohne `title` die Korrekturen der Zeile auflisten, mit `title` (Titel oder Regelkennung) die Korrektur anwenden; liefert den Diff |
