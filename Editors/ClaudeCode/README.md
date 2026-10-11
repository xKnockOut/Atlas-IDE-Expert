# Atlas in Claude Code

`AtlasServer.exe` muss im `PATH` liegen, sonst in `.lsp.json` und `.mcp.json` den vollen Pfad eintragen.

## Nur MCP-Werkzeuge (ein Befehl)

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

Alternativ `atlas/.mcp.json` ins Projekt kopieren (ohne `--root` gilt das Arbeitsverzeichnis). Werkzeuge siehe [docs/MCP.md](../../docs/MCP.md).

## LSP und MCP als Plugin

Der Ordner `atlas/` ist ein Plugin mit `.lsp.json` (Diagnosen, Navigation) und `.mcp.json`.

```
claude plugin validate Editors/ClaudeCode/atlas
claude --plugin-dir Editors/ClaudeCode/atlas
```

Ein dauerhaft installierbares Plugin mit Marketplace folgt in #101.
