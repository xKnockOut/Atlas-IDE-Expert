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
- Schreibende Werkzeuge haben `dryRun` mit Vorgabe `true`: Sie liefern dann nur den Diff.
  Mit `dryRun: false` schreiben sie atomar: Hat sich eine Datei seit dem Lesen geändert
  oder ist sie in der IDE ungespeichert geändert (das IDE-Plugin meldet das in
  `%LOCALAPPDATA%\Atlas\editor-dirty-<pid>.json`), wird nichts geschrieben; scheitert das Schreiben
  einer Datei, werden die schon geschriebenen zurückgesetzt. Kodierung und Zeilenenden
  bleiben erhalten (#121).
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
| `get_component_info` | `name` | published-Properties mit Typ und Default, Ereignisse mit Signatur, Vorfahrenkette, Palettenseite aus `RegisterComponents`, Package aus `contains` der .dpk; ohne Quellen ein Hinweis statt leerer Liste |
| `get_unit_outline` | `unit` | uses-Listen und Symbole einer Unit mit Zeilennummern |
| `find_references` | `name` | Verwendungen im Projekt mit Datei:Zeile und Quelltextzeile |
| `get_call_hierarchy` | `name`, `direction` | Aufrufer (`incoming`) und Aufgerufene (`outgoing`), Standard beides |
| `qualified_name` | `file`, `line`, `column`, `withParameters` (optional) | Voll qualifizierter Name des Symbols an der Stelle, z. B. `Vcl.Controls.TControl.Paint`; mit `withParameters` bei Routinen samt Parametertypen |
| `get_diagnostics` | `file` (optional) | Syntaxfehler und Regelbefunde einer Datei oder aller Projektdateien |
| `check_code` | `file`, `text`, `startLine`/`endLine` (optional) | Prüft geplanten Code ohne zu schreiben: Syntaxfehler, Regelbefunde, nicht auflösbare Bezeichner. Ohne Bereich ist `text` die ganze Unit, sonst der Ersatz für die Zeilen `startLine`..`endLine` |
| `get_dfm_info` | `file` | Komponentenbaum eines Text-Formulars mit Eigenschaften und Ereignissen |
| `get_last_build` | `project` (optional) | Letzter Build, den der Benutzer in der IDE gestartet hat (über das IDE-Plugin, #556): Ergebnis, Art, Zeitpunkt, Dauer, Projekt, Konfiguration, Plattform, Zahl der Fehler/Warnungen/Hinweise und alle Meldungen mit Datei, Zeile, Spalte (1-basiert), Code und Text; Meldungen außerhalb von `--root` bleiben weg. Ohne Build: „Noch kein Build …“. Austausch über `%LOCALAPPDATA%\Atlas\build-*.json`, die der LSP-Server schreibt |
| `explain_finding` | `file`, `line`, `rule` (optional) | Befunde einer Zeile als Markdown (#158): Regel mit Beschreibung, Codeausschnitt mit markierter Zeile, Vorher/Nachher-Beispiel aus dem Regelkatalog. |
| `rename_symbol` | `file`, `line`, `column`, `newName`, `dryRun` (Vorgabe `true`) | Schreibend (#61): benennt das Symbol an der Stelle projektweit um, samt `.dfm`/`.fmx` und automatisch benannter Ereignis-Handler; liefert den Diff aller Dateien |
| `apply_code_action` | `file`, `line`, `title` (optional), `dryRun` (Vorgabe `true`) | Schreibend (#61): ohne `title` die Korrekturen der Zeile auflisten, mit `title` (Titel oder Regelkennung) die Korrektur anwenden; liefert den Diff |
