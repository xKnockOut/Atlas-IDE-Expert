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
| `delphi://build/last` | Ergebnis und Compilermeldungen des letzten Builds in der IDE wie `get_last_build` (#1357, mit `mcp.prompts`) |

Ressourcen mit Vorlage (#1357, `resources/templates/list`) hängt man in Claude Code mit `@` an eine Frage, z. B. `@delphi:delphi://unit/UI.Auftrag`. Der Wert in `{…}` darf %-kodiert sein (`Source%2FA.pas`). Units und Pfade gelten wie Pfadparameter (#99): außerhalb des Arbeitsordners und seiner Such- und Bibliothekspfade ergibt das Lesen einen Fehler mit Begründung. Der Inhalt ist Markdown, höchstens 64 KB; darüber gekürzt mit Hinweis auf das Werkzeug für alles.

| Vorlage | Inhalt |
|---|---|
| `delphi://unit/{name}` | Gliederung (`get_unit_outline`) und interface-Teil einer Unit; `name` ist ein Unit-Name oder ein Pfad |
| `delphi://form/{file}` | Komponentenbaum eines Formulars (`get_dfm_info`); `file` ist die .dfm/.fmx oder die .pas dazu |
| `delphi://findings/{file}` | Syntaxfehler und Befunde der Prüfregeln einer Datei (`get_diagnostics`) |

## Prompts

Prompts (#1357) sind fertige Arbeitsabläufe. Claude Code zeigt sie nach `/` als Befehle `/mcp__delphi__<name>` mit Beschreibung und Argumenten. `prompts/get` liefert eine Nachricht mit Anleitung und den Ergebnissen der nötigen Werkzeuge; Claude muss nicht erst einzeln nachfragen, und jeder Ablauf ist jedes Mal gleich gründlich. Die Werkzeuge laufen dabei mit denselben Regeln wie `tools/call`: Abgeschaltete (`mcp.disabledTools`) fehlen im Text mit Begründung, mit `--restricted` bieten die Anleitungen keine schreibenden Schritte an (keine Korrekturen, kein `run_tests`, kein Commit; Vorschläge als Diff).

| Prompt | Argumente | Was die Nachricht enthält |
|---|---|---|
| `unit_review` | `unit` | Gliederung, Befunde (`get_diagnostics`), Metriken über Grenzwert (`get_metrics`), ungenutzter Code (`find_unused_code`), `delphi://conventions`; Anleitung für ein Review nach Schweregrad mit Vorschlägen und `check_code` vor jeder Änderung |
| `explain_form` | `file` | Komponentenbaum (`get_dfm_info`), Ereignis-Handler mit Rümpfen aus der Unit (gemeinsame Handler einmal mit allen Komponenten), Datenbindungen (`DataSource`, `DataField`, `Connection`, LiveBindings …); Anleitung für eine Erklärung des Formulars |
| `write_tests` | `name` | Deklaration (`get_declaration`), Aufrufer (`get_call_hierarchy`), Auswirkungen mit den vorhandenen Tests (`get_impact`), DUnitX-Konventionen des Projekts (`testUnits.pattern`, `.folder`, `.project`); Anleitung für neue Testmethoden in der passenden Testunit und Lauf mit `run_tests` |
| `fix_finding` | `file`, `line`, optional `rule` | Erklärung (`explain_finding`), Codeausschnitt ±8 Zeilen mit markierter Zeile, verfügbare Korrekturen (`apply_code_action` ohne `title`); Anleitung: erst die Ursache, dann die Korrektur, dann `check_code` |
| `prepare_commit` | optional `base` | geänderte Dateien laut Git oder SVN (ohne `base` die nicht eingecheckten gegenüber HEAD, sonst seit der Abzweigung von `base`), neue Befunde nur in geänderten Zeilen (wie `--changed-lines`), betroffene Tests (mit `get_affected_tests` aus #1353, sonst der Hinweis auf `get_impact`), Commit-Präfix des aktuellen Issues (`issues.commitPattern`, vom Plugin in `<gitdir>/atlas-commit-prefix`); Anleitung für Prüfung und Commit-Nachricht |

Beispiele in Claude Code:

```
/mcp__delphi__unit_review UI.Auftrag
/mcp__delphi__explain_form Source\UI.Auftrag.dfm
/mcp__delphi__write_tests TAuftrag.Speichern
/mcp__delphi__fix_finding Source\UI.Auftrag.pas 42 empty-except
/mcp__delphi__prepare_commit main
@delphi:delphi://unit/UI.Auftrag Wo wird hier die Mehrwertsteuer berechnet?
```

Die Anleitungen sind deutsch, mit `"mcp": { "promptLanguage": "en" }` englisch. `"mcp": { "prompts": false }` schaltet Prompts und Vorlagen ab: `prompts/list` und `resources/templates/list` sind dann leer, `delphi://build/last` fehlt; die Werkzeuge bleiben. Beide Schlüssel stehen in der globalen `settings.json` (Seite *MCP*).

Eigene Prompts des Projekts stehen in `atlas.json` unter `mcp.customPrompts`. Platzhalter `{argument}` im Text werden ersetzt (unbekannte bleiben stehen), `include` hängt Ergebnisse an: `outline`, `diagnostics`, `metrics`, `unused`, `todos`, `form`, `impact`, `dependencies`, `conventions`, `lastBuild`. Die Inhalte nehmen das Argument `file`, `unit` oder (bei `impact`) `name`; eine Unit wird für Datei-Inhalte wie bei `unit_review` aufgelöst. Die Namen der eingebauten Prompts sind vergeben: Ein eigener mit gleichem Namen fehlt in der Liste.

```json
{
  "mcp": {
    "customPrompts": [
      {
        "name": "check_unit",
        "description": "Unit vor dem Review prüfen",
        "arguments": [{ "name": "unit", "description": "Unit-Name", "required": true }],
        "text": "Prüfe {unit}: Befunde zuerst, dann Methoden über den Grenzwerten.",
        "include": ["diagnostics", "metrics"]
      }
    ]
  }
}
```

Prompts gegenüber den Befehlen des Claude-Code-Plugins (`/atlas:bauen`): Die Plugin-Befehle sind Abläufe mit Hooks und Werkzeugen auf dem Rechner (bauen, Tests laufen lassen); Prompts sind alles, was die Daten vom Server bekommt, und funktionieren in jedem MCP-Programm. Im IDE-Plugin wirken sie nicht.

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
| `get_architecture` | `section` (`overview`, `central`, `subsystems`, `cycles`, `crossLinks`; Vorgabe `overview`), `unit` (optional), `compareWith` (optional, Pfad relativ zum Projekt), `resolution` (optional, 0,2 bis 5,0; Feinheit der Teilsysteme für diesen Aufruf, sonst `architecture.grouping.resolution`, #1366) | Architekturübersicht (#1118) aus dem uses-Graphen: Teilsysteme (Louvain-Gruppen eng verbundener Units, übergroße und lose nachgeteilt und als „Teil von …“ gekennzeichnet, #1364) mit Namen, zentrale Units, Zyklen und Querverbindungen zwischen Teilsystemen, je mit Datei:Zeile der uses-Einträge; mit `unit` der Steckbrief einer Unit; mit `compareWith` (gespeicherter Stand aus `AtlasServer --architecture <Datei.json>` oder „Stand speichern …“, #1121) die Abschnitte des Vergleichs: neue und entfernte Zyklen, Querverbindungen und uses-Kanten zwischen Teilsystemen, Teilsystemwechsel, gewachsene zentrale Units, neue und entfernte Units und welche Arten aus `architecture.failOn` vorkommen. Umfang (`architecture.scope`), Bibliotheks-Units und Ausschlüsse aus `atlas.json`; dieselben Zahlen wie das Fenster „Atlas-Architektur“ und `--architecture`. Mit `architecture.enabled` = false nicht angeboten |
| `query_code` | `query` (Abfrage oder `@name`; leer = Kurzhilfe mit allen Mengen, Feldern und Prädikaten), `format` (`markdown` oder `json`), `limit` (Vorgabe 200) | Code-Abfragen über den Index (#1351): `<Menge> where <Bedingung> [order by <Feld> [asc\|desc]] [limit n]` über `units`, `classes`, `records`, `interfaces`, `methods`, `routines`, `fields`, `properties`, `forms`; Felder wie `name`, `unit`, `visibility`, `methods`, `lines`, `complexity`, `cognitive`, `nesting`, `params`, `callers`, `callees`, `overrides`, `uses`, `usedBy`, `ancestor`, `components`; Prädikate `inherits` (transitiv), `implements`, `uses`, `calls`, `has attribute`, Vergleiche, `like` mit `*`/`?`, `and`, `or`, `not`, Klammern. Zahlen wie `get_metrics` und `find_unused_code`; erschlossene Aufrufe (#1119) zählen mit und sind markiert. Ein Fehler kommt deutsch mit Spalte und Vorschlag. Gespeicherte Abfragen aus `queries` in `atlas.json` über `@name`. Lesend; fehlt mit `query.enabled` aus |
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
| `format_code` | `file`, `text` (optional), `startLine`/`endLine` (optional, ab 1), `dryRun` (Vorgabe `true`) | Schreibend (#1358): formatiert die Unit nach den Formatregeln des Projekts (`format.*` in `atlas.json`, `.editorconfig`) wie *Dokument formatieren* in der IDE, ganz oder nur `startLine`..`endLine` (ohne `endLine` eine Zeile). Mit `text` (geplanter Inhalt der ganzen Unit, wie bei `check_code`) liefert es die Abweichungen und den formatierten Text und schreibt nie; sonst zeigt es die Abweichungen (Zeile und Art) und den Diff, mit `dryRun: false` schreibt es wie `apply_code_action` (in der IDE offene Dateien über das Plugin als ein Rückgängig-Schritt, #397). Dateien mit Syntaxfehlern formatiert es nicht (Werkzeugfehler mit Zeile); `// atlas-format: off` … `on` bleibt unverändert. Die Zeilenenden der Datei bleiben; `format.endOfLine` setzt `AtlasServer --check <Datei> --format-write` um |

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
pwsh Tools/Start-McpInspector.ps1 -Method prompts/get -Prompt unit_review -Arguments @{ unit = 'Shell.Mcp' }
pwsh Tools/Start-McpInspector.ps1 -Method resources/read -Uri delphi://unit/Shell.Mcp
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

- `initialize`, `tools/list`, `resources/list`, `resources/templates/list` und `prompts/list` antworten ohne Fehler.
- Jedes Werkzeug hat eine Beschreibung, `inputSchema` vom Typ `object`, jeder Pflichtparameter steht in `properties`, jeder Parameter hat eine Beschreibung.
- Jedes Werkzeug antwortet auf sein Beispiel ohne JSON-RPC-Fehler, ohne `isError` und nicht leer, und die Antwort enthält den erwarteten Text.
- Jede Ressource lässt sich lesen.
- Jeder Prompt hat eine Beschreibung, jedes Argument eine Beschreibung, und `prompts/get` liefert mit dem Beispiel unter `prompts` eine nicht leere Nachricht mit dem erwarteten Text; jede Vorlage liest sich mit der Beispiel-URI unter `templates` (#1357). Ein Prompt oder eine Vorlage ohne Beispiel lässt den Lauf scheitern.

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
