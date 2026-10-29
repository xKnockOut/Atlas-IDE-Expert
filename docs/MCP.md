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
| `get_declaration` | `name` | Quelltext der Deklaration, auch aus RTL/VCL; dazu der Abschnitt „Begründungen:“ (#1123) mit `// WHY:`, `// HACK:`, `// NOTE:` … über der Deklaration und im Rumpf der Implementierung, je Eintrag Marke, Zeile und Text (aus mit `hints.rationale`) |
| `get_type_hierarchy` | `name` | Vorfahren bis zur Wurzel, Nachfahren rekursiv |
| `get_component_info` | `name` | published-Properties mit Typ und Default (ausdrücklich, implizit, `nodefault`, `stored`), Ereignisse mit Signatur, Vorfahrenkette, Palettenseite aus `RegisterComponents`, Package aus `contains` der .dpk; ohne Quellen ein Hinweis statt leerer Liste |
| `get_unit_outline` | `unit` | uses-Listen und Symbole einer Unit mit Zeilennummern |
| `find_references` | `name` | Verwendungen im Projekt mit Datei:Zeile und Quelltextzeile; zuerst die sicheren, dann „Erschlossen, vor dem Umbenennen prüfen:“ mit Grund und Erklärung (Interface, überschriebene Methode, unklare Überladung, unbekannter Typ, inaktiver Zweig, Text), Kopfzeile „n Verwendungen …, a sicher, b erschlossen“ (#1119, `references` in atlas.json) |
| `get_call_hierarchy` | `name`, `direction` | Aufrufer (`incoming`) und Aufgerufene (`outgoing`), Standard beides; erschlossene Aufrufer stehen nach den sicheren mit Grund (#1119); Aufrufe über ein Interface oder eine virtuelle Methode tragen „[über Interface, n Umsetzungen]“ bzw. „[virtuell, n Umsetzungen]“ (#1122) |
| `get_impact` | `name`, `depth` (1–5, optional), `format` (`text` oder `json`) | Auswirkungsanalyse (#1120): was betroffen ist, wenn sich das Symbol ändert. Aufrufer und Verweise, Overrides, überschriebene Basismethode, Interface-Methode und Umsetzungen, Formularbindungen; als Baum nach Ebenen und Ursache, erschlossene Treffer mit Grund. Danach die betroffenen DUnitX-Tests und eine Zeile `run_tests tests: …` mit den Namen für `run_tests`, am Ende erreichte Grenzen (Tiefe, 1000 Stellen, 60 s). Ohne `depth` gilt `navigation.impactDepth`; `json` liefert dasselbe wie `atlas/impact` |
| `qualified_name` | `file`, `line`, `column`, `withParameters` (optional) | Voll qualifizierter Name des Symbols an der Stelle, z. B. `Vcl.Controls.TControl.Paint`; mit `withParameters` bei Routinen samt Parametertypen |
| `get_diagnostics` | `file` (optional) | Syntaxfehler und Regelbefunde einer Datei oder aller Projektdateien |
| `hook_check` | `file`, `severity` (`error`, `warning`, `information`, `hint`; Vorgabe `warning`) | Für Hooks von Claude Code: Befunde ab `severity` einer gerade bearbeiteten Datei als Ausgabe eines PostToolUse-Hooks (`{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}`), damit Claude sie gleich nach Edit/Write sieht. Leer (kein Hinweis) bei Dateien ohne Endung `.pas`, `.dpr`, `.dpk`, `.inc`, außerhalb des Arbeitsbereichs oder ohne Befunde. Das Plugin `atlas` ruft es über `hooks/hooks.json` auf; abschalten mit `"mcp": {"disabledTools": ["hook_check"]}` |
| `get_metrics` | `file` (optional), `format` (`markdown` oder `json`) | Code-Metriken je Methode (#66): Länge in Codezeilen, Verschachtelungstiefe, zyklomatische und kognitive Komplexität, Parameteranzahl; Bericht mit den Methoden über einem Grenzwert aus `atlas.json` (Regeln `metric-*`, Option `max`) oder die Metrikdaten als JSON |
| `get_todos` | `file`, `unit`, `category`, `owner`, `keyword`, `includeDone` (alle optional), `format` (`markdown` oder `json`) | TODO-Übersicht (#68) aller Dateien, die das Projektmodell dem Projekt zuordnet: `// TODO`, `// FIXME` und das Format der IDE-To-Do-Liste `{ TODO 1 -oPerson -cKategorie : Text }` mit Priorität, Person und Kategorie, gefiltert nach Unit, Kategorie, Person oder Marke; erledigte Einträge (`{ DONE … }`) nur mit `includeDone`. Weitere Marken über die Option `keywords` der Regel `todo-comment`. Markdown mit Zählung nach Kategorie und Person und je Unit einer Tabelle, oder JSON (`format` 1, Zeilen ab 1) |
| `get_rationale` | `unit` oder `name` | Begründungen (#1123) einer Unit (Kommentare im interface vor dem ersten Typ und alle Symbole mit Fundstelle) oder eines Symbols (über der Deklaration und im Rumpf der Implementierung), je Eintrag Marke, Zeile ab 1 und Text. Marken aus `hints.rationaleMarkers` (Vorgabe `NOTE`, `WHY`, `HACK`, `IMPORTANT`, `RATIONALE`); Marken der TODO-Übersicht erscheinen nie. Gilt auch bei `hints.rationale` aus; abschaltbar über `mcp.disabledTools` |
| `get_architecture` | `section` (`overview`, `central`, `subsystems`, `cycles`, `crossLinks`; Vorgabe `overview`), `unit` (optional), `compareWith` (optional, Pfad relativ zum Projekt) | Architekturübersicht (#1118) aus dem uses-Graphen: Teilsysteme (Louvain-Gruppen eng verbundener Units) mit Namen, zentrale Units, Zyklen und Querverbindungen zwischen Teilsystemen, je mit Datei:Zeile der uses-Einträge; mit `unit` der Steckbrief einer Unit; mit `compareWith` (gespeicherter Stand aus `AtlasServer --architecture <Datei.json>` oder „Stand speichern …“, #1121) die Abschnitte des Vergleichs: neue und entfernte Zyklen, Querverbindungen und uses-Kanten zwischen Teilsystemen, Teilsystemwechsel, gewachsene zentrale Units, neue und entfernte Units und welche Arten aus `architecture.failOn` vorkommen. Umfang (`architecture.scope`), Bibliotheks-Units und Ausschlüsse aus `atlas.json`; dieselben Zahlen wie das Fenster „Atlas-Architektur“ und `--architecture`. Mit `architecture.enabled` = false nicht angeboten |
| `find_unused_code` | `file` (optional), `format` (`markdown` oder `json`) | Ungenutzter Code (#64) einer Datei oder aller Projektdateien mit dem Index aller Projekte der Gruppe wie im Editor: die Befunde von `unused-private-member`, `unused-public-member`, `unused-declaration` und `unused-unit` mit Zeile, Spalte, Regel und Konfidenz, je Datei ein Abschnitt (höchstens 200 Befunde). Schweregrad, `off`, Optionen und `deadCode.keepAttributes`/`keepPatterns` aus `atlas.json` gelten. Solange Projekte laden oder der Index läuft, schweigen die projektweiten Regeln; der Bericht sagt das (JSON: `incomplete`) |
| `get_unit_dependencies` | `unit` (Name oder Pfad), `direction` (`uses`, `usedBy`, `both`; Vorgabe `both`), `transitive` (optional), `format` (`markdown` oder `json`) | Abhängigkeiten einer Unit aus dem Uses-Graphen (#64, #268): direkte uses und die Units, die sie verwenden, je mit Abschnitt (`interface`/`implementation`), mit `transitive` die Hüllen in beide Richtungen, dazu die Zyklen durch die Unit mit vollständigem Pfad (reine interface-Zyklen als Compilerfehler wie F2047). Nur Units der Projekte, ohne RTL/VCL |
| `find_path` | `from`, `to` (wie bei `find_symbol`: Typ, `TFoo.Bar`, Routine, Feld, Property oder Unit), `via` (optional: `uses`, `inherits`, `implements`, `hasField`, `parameter`, `result`, `calls`, `contains`, `library`; Vorgabe alle Kantenarten, Bibliotheks-Units kein Durchgang), `maxSteps` (1–16, Vorgabe 8), `all` (alle gleich kurzen Wege, höchstens 5) | Kürzester Weg zwischen zwei Symbolen oder Units (#1117) in einem Aufruf: „Kürzester Weg (N Schritte):“, je Knoten Symbol und Datei:Zeile, je Schritt Kantenart (verwendet, erbt von, setzt um / umgesetzt von, hat Feld / vom Typ, Parameter vom Typ, Ergebnis vom Typ, ruft auf, enthält) mit Fundstelle; nur erschlossene Kanten (mehrere Umsetzungen) tragen `[erschlossen]`. Zweistufig: erst über die Kanten des Index (bidirektionale Breitensuche), Aufrufkanten nur für Routinen auf Kandidatenwegen. Gleich lange Wege eindeutig sortiert (Rangfolge der Kantenarten, dann Name). „Kein Weg in höchstens N Schritten.“ ist verlässlich; bei Zeitlimit (`requestTimeoutMs`), Abbruch (`notifications/cancelled`) oder 20 000 Knoten „Kein Weg gefunden in N Schritten (Suche nach X Knoten abgebrochen: Grund).“; mehrdeutiger Name: Trefferliste mit Fundstellen. Mit `via: ["uses"]` dasselbe Ergebnis wie der kürzeste Weg der Architekturkarte. Mit `navigation.symbolPath` = false nicht angeboten |
| `check_code` | `file`, `text`, `startLine`/`endLine` (optional) | Prüft geplanten Code ohne zu schreiben: Syntaxfehler, Regelbefunde, nicht auflösbare Bezeichner. Ohne Bereich ist `text` die ganze Unit, sonst der Ersatz für die Zeilen `startLine`..`endLine` |
| `get_dfm_info` | `file` | Komponentenbaum eines Text-Formulars mit Eigenschaften und Ereignissen |
| `get_last_build` | `project` (optional) | Letzter Build, den der Benutzer in der IDE gestartet hat (über das IDE-Plugin, #556): Ergebnis, Art, Zeitpunkt, Dauer, Projekt, Konfiguration, Plattform, Zahl der Fehler/Warnungen/Hinweise und alle Meldungen mit Datei, Zeile, Spalte (1-basiert), Code und Text; Meldungen außerhalb von `--root` bleiben weg. Ohne Build: „Noch kein Build …“. Austausch über `%LOCALAPPDATA%\Atlas\build-*.json`, die der LSP-Server schreibt |
| `build_project` | `project`, `mode` (`make`, `build`, `check`; Vorgabe `make`), `configuration`, `platform` (alle optional) | Startet einen Prozess (#261): baut ein Projekt in der laufenden RAD-Studio-IDE über das Atlas-Plugin (IOTAProjectBuilder), auch ohne Kommandozeilen-Compiler (Starter Edition), und liefert das Ergebnis wie `get_last_build`. Das Projekt muss in einer IDE mit Atlas-Plugin offen sein; ohne `project` das aktive Projekt, wenn es unter `--root` liegt. Konfiguration und Plattform gelten nur für diesen Build. Austausch über `%LOCALAPPDATA%\Atlas\ide-builds\<pid>\`; nimmt das Plugin den Auftrag nicht binnen 5 s an (abgeschaltet über „Builds für Claude Code“, Debugger oder anderer Build aktiv), meldet das Werkzeug den Grund |
| `run_tests` | `project`, `tests` (Liste aus `Unit.Fixture` oder `Unit.Fixture.Methode`), `build` (Vorgabe `false`), `configuration`, `platform`, `timeoutSeconds` (Vorgabe 600, höchstens 3600; alle optional) | Startet einen Prozess (#69): führt die DUnitX-Tests eines Testprojekts aus. Testprojekt ist ein `.dproj` unter `--root`, dessen Hauptdatei `DUnitX.TestFramework` verwendet; ohne `project` das einzige solche. Die Plattform kommt aus dem Projekt (Vorgabe der Datei, sonst die erste aktivierte; ein Projekt nur für Win64 läuft als Win64), die Test-EXE aus `DCC_ExeOutput` und der Hauptdatei. Eine vorhandene EXE läuft ohne Compiler; mit `build: true` baut es vorher in der laufenden IDE wie `build_project` (ohne IDE mit Atlas-Plugin meldet es den Grund, schlägt der Build fehl, laufen keine Tests). Aufruf mit `--exitbehavior:Continue --xmlfile:<temp> [--run:…]`; das Testprogramm braucht den XML-Logger von DUnitX (`TDUnitXXMLNUnitFileLogger`, wie in der Vorlage von RAD Studio), sonst `result: noReport` mit den letzten Zeilen der Ausgabe. Ergebnis als JSON: `result` (`passed`, `failed`, `noTests`, `noReport`), Projekt, Konfiguration, Plattform, EXE, Exit-Code, Zahlen (`total`, `passed`, `failed`, `errors`, `skipped`, `durationMs`) und je fehlgeschlagenem Test (höchstens 100) Name, Meldung, `expected`/`actual` (aus „Expected … but got …“), Datei und Zeile (1-basiert) des Methodenkopfs. Läufe über MCP stehen nicht in der Projekt-Zusammenfassung der Willkommensseite; das tun nur Läufe aus der IDE |
| `explain_finding` | `file`, `line`, `rule` (optional) | Befunde einer Zeile als Markdown (#158): Regel mit Beschreibung, Codeausschnitt mit markierter Zeile, Vorher/Nachher-Beispiel aus dem Regelkatalog. |
| `rename_symbol` | `file`, `line`, `column`, `newName`, `dryRun` (Vorgabe `true`) | Schreibend (#61): benennt das Symbol an der Stelle projektweit um, samt `.dfm`/`.fmx` und automatisch benannter Ereignis-Handler; liefert den Diff aller Dateien. Erschlossene Stellen (über Interface, überschrieben, unbekannter Typ, Text) bleiben unverändert und stehen unter „Nicht geändert, bitte prüfen“ (#1119) |
| `apply_code_action` | `file`, `line`, `title` (optional), `dryRun` (Vorgabe `true`) | Schreibend (#61): ohne `title` die Korrekturen der Zeile auflisten, mit `title` (Titel oder Regelkennung) die Korrektur anwenden; liefert den Diff |

## Werkzeuge entwickeln und prüfen

Neue oder geänderte Werkzeuge erst ohne Claude prüfen (#1125). Zwei Skripte, beide unter `pwsh` (Windows, Linux) und Windows PowerShell 5.1:

| Skript | Wofür |
|---|---|
| `Tools/Start-McpInspector.ps1` | [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) gegen AtlasServer: Werkzeuge, Ressourcen und Eingabeschemas so, wie ein Client sie sieht, Aufrufe mit eigenen Argumenten und die rohen JSON-RPC-Nachrichten |
| `Tools/Test-McpTools.ps1` | Probelauf: jedes Werkzeug einmal mit Beispielargumenten in einer Serversitzung, Schema- und Antwortprüfung, roher Mitschnitt als JSON Lines |

Das trennt Fehler im Server von Fehlern in Beschreibung oder Schema, die nur dazu führen, dass Claude ein Werkzeug falsch aufruft. Server ist ohne `-Server` `Output\Win64\Debug\Bin\AtlasServer.exe`, unter Linux `Output/Linux64/Bin/AtlasServer`, sonst `AtlasServer` aus dem PATH. Der Inspector braucht Node.js ab 22.19 und wird beim ersten Aufruf in fester Version geladen.

### MCP Inspector

```powershell
# Oberfläche im Browser: links Server verbinden, oben "Tools", rechts "Messages" mit jedem Aufruf roh
pwsh Tools/Start-McpInspector.ps1 -ProjectRoot Tests/Referenzprojekt

# Oberfläche im Terminal (SSH, Cloud-Sitzung)
pwsh Tools/Start-McpInspector.ps1 -Tui

# Kommandozeile, ein Aufruf, Ergebnis als JSON
pwsh Tools/Start-McpInspector.ps1 -Method tools/list -Strict
pwsh Tools/Start-McpInspector.ps1 -Method tools/call -Tool qualified_name -Arguments @{ file = 'Application/AtlasServer.dpr'; line = 1; column = 9; withParameters = $true }
pwsh Tools/Start-McpInspector.ps1 -Method resources/read -Uri delphi://conventions -Output konventionen.json
```

- `-Strict` gibt bei `tools/list` die Schema-Prüfung des Inspectors aus (Pfad, Problem, Vorschlag) und endet mit Exit-Code 6, wenn ein Schema bei Clients nicht portabel ist.
- `-Restricted` startet den Server mit `--restricted` (nur lesende Werkzeuge), `-Log` mit `--log`.
- Der Server startet über eine erzeugte Sitzungskonfiguration (`--config`); Schalter wie `--mcp` landen so beim Server, nicht beim Inspector. Geheimnisse hält der Inspector nur im Speicher (`MCP_INSPECTOR_SECRET_STORE=memory`), Atlas braucht keine.

Ohne PowerShell, z. B. in einer Cloud-Sitzung mit dem Linux-Server:

```bash
npx -y @modelcontextprotocol/inspector@2.12.0 --cli AtlasServer --mcp --root . --method tools/call \
  --tool-name hook_check --tool-arg file=Application/Source/Shell/Shell.Mcp.pas
```

### Probelauf aller Werkzeuge

```powershell
pwsh Tools/Test-McpTools.ps1                       # alle Werkzeuge, Ordner Tests/Referenzprojekt
pwsh Tools/Test-McpTools.ps1 -Tool find_symbol -Arguments @{ name = 'TKundenSuche' }
pwsh Tools/Test-McpTools.ps1 -Tool run_tests -WithProcessTools -Arguments @{ tests = @('Unit.Fixture') }
```

Das Skript spricht den Server direkt über stdio an. Der Index entsteht nur einmal, der ganze Lauf dauert wenige Sekunden (der Inspector startet den Server je Kommandozeilenaufruf neu). Geprüft wird:

- `initialize`, `tools/list`, `resources/list` und `resources/templates/list` antworten ohne Fehler.
- Jedes Werkzeug hat eine Beschreibung, `inputSchema` vom Typ `object`, jeder Pflichtparameter steht in `properties`, jeder Parameter hat eine Beschreibung.
- Jedes Werkzeug antwortet auf sein Beispiel ohne JSON-RPC-Fehler, ohne `isError` und nicht leer, und die Antwort enthält den erwarteten Text.
- Jede Ressource lässt sich lesen.

Die Beispiele stehen in `Tools/Mcp/Werkzeug-Beispiele.json` und beziehen sich auf das Referenzprojekt (`Tests/Referenzprojekt`). Zeilen und Spalten stehen dort als Platzhalter (`{{zeile:procedure TRefAnzeige.SetStil}}`, `{{spalte:SetStil}}`), damit verschobene Zeilen die Beispiele nicht brechen. Werkzeuge mit `"process": true` (`build_project`, `run_tests`) brauchen die IDE oder ein Testprojekt und laufen nur mit `-WithProcessTools`. Mit `-Tool` und `-Arguments` ruft das Skript ein Werkzeug mit eigenen Argumenten auf, auch mit Listen und Objekten, und gibt die Antwort aus.

Der Mitschnitt (`Output/Mcp/probe-<Zeit>.jsonl`) enthält jede Nachricht roh, eine je Zeile: `{"zeit":"…","richtung":"an Server"|"vom Server","nachricht":{…}}`. Exit-Code 0: alles in Ordnung, 1: Befunde, 3: Server fehlt oder antwortet nicht.

### Ablauf für ein neues Werkzeug

1. Werkzeug in `Shell.Mcp.pas` registrieren, Logik in `Atlas.Common.Mcp.*` mit DUnitX-Tests.
2. Zeile in der Tabelle oben ergänzen; `TMcpShellTests.ToolsListMatchesDocumentation` prüft das.
3. Beispiel in `Tools/Mcp/Werkzeug-Beispiele.json` eintragen; ohne Eintrag scheitert der Probelauf.
4. Bauen, dann `pwsh Tools/Start-McpInspector.ps1 -Method tools/list -Strict` und `pwsh Tools/Test-McpTools.ps1`.
5. Grenzfälle im Inspector von Hand: fehlende Pflichtparameter, falsche Typen, unbekannte Dateien, große Ergebnisse.

Worauf achten:

- Beschreibung und Parameterbeschreibungen sagen, wann das Werkzeug hilft und was es liefert; Claude wählt nur danach aus.
- Pflichtparameter stehen in `required`; ein fehlender Pflichtparameter liefert eine verständliche Fehlermeldung (`EMcpToolError`), keine Ausnahme mit Stapel.
- Große Ergebnisse sind begrenzt (z. B. `MaxFindings`) und sagen, wie viel weggelassen wurde.
