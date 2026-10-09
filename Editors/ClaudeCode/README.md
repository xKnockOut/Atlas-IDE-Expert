# Argus in Claude Code

`ArgusServer.exe` muss im `PATH` liegen, sonst in `.lsp.json` und `.mcp.json` den vollen Pfad eintragen.

## Nur MCP-Werkzeuge (ein Befehl)

```
claude mcp add delphi -- ArgusServer.exe --mcp --root C:\Projekte\App
```

Alternativ `argus/.mcp.json` ins Projekt kopieren (ohne `--root` gilt das Arbeitsverzeichnis). Werkzeuge siehe [docs/MCP.md](../../docs/MCP.md).

## LSP und MCP als Plugin

Der Ordner `argus/` ist ein Plugin mit `.lsp.json` (Diagnosen, Navigation) und `.mcp.json`.

```
claude plugin validate Editors/ClaudeCode/argus
claude --plugin-dir Editors/ClaudeCode/argus
```

Ein dauerhaft installierbares Plugin mit Marketplace folgt in #101.
