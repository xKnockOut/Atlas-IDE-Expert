# MCP-Modus

Mit `--mcp` bietet Argus den Symbolindex eines Projektordners über das
Model Context Protocol an (stdio, eine JSON-Nachricht je Zeile). Ein KI-Assistent
kann damit Fragen zum Projekt beantworten, ohne Quelldateien vollständig zu lesen.

```
claude mcp add delphi -- ArgusServer.exe --mcp --root C:\Projekte\App
```

`--root` ist der Ordner mit `argus.json` bzw. der .dproj; ohne Angabe das
aktuelle Verzeichnis. `--log <Datei>` schreibt ein Protokoll, stdout gehört allein
dem Protokoll.

Pfadparameter (#99): relativ zu `--root` oder absolut; sie werden normalisiert
(`..`, Junctions, Symlinks, subst-Laufwerke aufgelöst) und nur im Arbeitsordner
sowie in den Such- und Bibliothekspfaden des Projekts angenommen. Alles andere
ergibt einen Werkzeugfehler mit Begründung. Schreibende Werkzeuge und solche mit
Prozessstart gibt es noch nicht; für sie gelten Vorschau, Protokoll und
Abschaltbarkeit aus #99, sobald sie kommen (#61, #69).

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
| `get_last_build` | `project` (optional) | Letzter Build, den der Benutzer in der IDE gestartet hat (über das IDE-Plugin, #556): Ergebnis, Art, Zeitpunkt, Dauer, Projekt, Konfiguration, Plattform, Zahl der Fehler/Warnungen/Hinweise und alle Meldungen mit Datei, Zeile, Spalte (1-basiert), Code und Text; Meldungen außerhalb von `--root` bleiben weg. Ohne Build: „Noch kein Build …“. Austausch über `%LOCALAPPDATA%\Argus\build-*.json`, die der LSP-Server schreibt |
