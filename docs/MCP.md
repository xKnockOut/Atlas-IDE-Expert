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

| Werkzeug | Parameter | Ergebnis |
|---|---|---|
| `find_symbol` | `name` | Fundstellen mit Art, Typ, Unit, Datei:Zeile; ohne exakten Treffer Teilstring-Suche |
| `get_declaration` | `name` | Quelltext der Deklaration, auch aus RTL/VCL |
| `get_type_hierarchy` | `name` | Vorfahren bis zur Wurzel, Nachfahren rekursiv |
| `get_component_info` | `name` | published-Properties mit Typ und Default, Ereignisse mit Signatur, Vorfahrenkette, Palettenseite aus `RegisterComponents`, Package aus `contains` der .dpk; ohne Quellen ein Hinweis statt leerer Liste |
| `get_unit_outline` | `unit` | uses-Listen und Symbole einer Unit mit Zeilennummern |
| `find_references` | `name` | Verwendungen im Projekt mit Datei:Zeile und Quelltextzeile |
| `get_call_hierarchy` | `name`, `direction` | Aufrufer (`incoming`) und Aufgerufene (`outgoing`), Standard beides |
| `get_diagnostics` | `file` (optional) | Syntaxfehler und Regelbefunde einer Datei oder aller Projektdateien |
| `check_code` | `file`, `text`, `startLine`/`endLine` (optional) | Prüft geplanten Code ohne zu schreiben: Syntaxfehler, Regelbefunde, nicht auflösbare Bezeichner. Ohne Bereich ist `text` die ganze Unit, sonst der Ersatz für die Zeilen `startLine`..`endLine` |
| `get_dfm_info` | `file` | Komponentenbaum eines Text-Formulars mit Eigenschaften und Ereignissen |
