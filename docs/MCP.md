# MCP-Modus

Mit `--mcp` bietet BetterDelphiLSP den Symbolindex eines Projektordners über das
Model Context Protocol an (stdio, eine JSON-Nachricht je Zeile). Ein KI-Assistent
kann damit Fragen zum Projekt beantworten, ohne Quelldateien vollständig zu lesen.

```
claude mcp add delphi -- BetterDelphiLSP.exe --mcp --root C:\Projekte\App
```

`--root` ist der Ordner mit `delphi-lsp.json` bzw. der .dproj; ohne Angabe das
aktuelle Verzeichnis. `--log <Datei>` schreibt ein Protokoll, stdout gehört allein
dem Protokoll.

| Werkzeug | Parameter | Ergebnis |
|---|---|---|
| `find_symbol` | `name` | Fundstellen mit Art, Typ, Unit, Datei:Zeile; ohne exakten Treffer Teilstring-Suche |
| `get_declaration` | `name` | Quelltext der Deklaration, auch aus RTL/VCL |
| `get_type_hierarchy` | `name` | Vorfahren bis zur Wurzel, Nachfahren rekursiv |
| `get_unit_outline` | `unit` | uses-Listen und Symbole einer Unit mit Zeilennummern |
| `get_dfm_info` | `file` | Komponentenbaum eines Text-Formulars mit Eigenschaften und Ereignissen |

Noch offen (#48): `find_references`, `get_call_hierarchy`, `get_diagnostics`.
