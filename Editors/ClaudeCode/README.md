# BetterDelphiLSP in Claude Code

`BetterDelphiLSP.exe` muss im `PATH` liegen, sonst in `.lsp.json` und `.mcp.json` den vollen Pfad eintragen.

## Nur MCP-Werkzeuge (ein Befehl)

```
claude mcp add delphi -- BetterDelphiLSP.exe --mcp --root C:\Projekte\App
```

Alternativ `betterdelphilsp/.mcp.json` ins Projekt kopieren (ohne `--root` gilt das Arbeitsverzeichnis). Werkzeuge siehe [docs/MCP.md](../../docs/MCP.md).

## LSP und MCP als Plugin

Der Ordner `betterdelphilsp/` ist ein Plugin mit `.lsp.json` (Diagnosen, Navigation) und `.mcp.json`.

```
claude plugin validate Editors/ClaudeCode/betterdelphilsp
claude --plugin-dir Editors/ClaudeCode/betterdelphilsp
```

Ein dauerhaft installierbares Plugin mit Marketplace folgt in #101.
