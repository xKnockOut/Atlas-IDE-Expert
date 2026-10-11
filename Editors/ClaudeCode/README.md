# Atlas in Claude Code

## Installation

### Als Plugin aus dem Marketplace (empfohlen)

1. `AtlasServer.exe` in einen Ordner im `PATH` legen ([Server besorgen](../../docs/Installation.md#server-besorgen)).
2. In Claude Code:

   ```
   /plugin marketplace add xKnockOut/Atlas-IDE-Expert
   /plugin install atlas@atlas
   ```

Das Plugin bringt mit:

- **LSP** (`.lsp.json`): Diagnosen und Navigation für `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm` und `.fmx`
- **MCP** (`.mcp.json`): die Werkzeuge aus [docs/MCP.md](../../docs/MCP.md) und die Ressource `delphi://conventions`
- **Skill** `delphi-mit-atlas`: wann welches Werkzeug hilft (z. B. `find_symbol` statt Textsuche, `rename_symbol` statt Suchen und Ersetzen)

Ohne `PATH`: Jedes Release enthält `atlas-claude-plugin-<Version>.zip` mit der EXE unter `bin/`. Entpacken und mit `claude --plugin-dir <Ordner>/atlas` starten oder den Ordner als lokalen Marketplace eintragen.

Die Version von Plugin und Marketplace-Eintrag setzt `Tools/Set-Version.ps1` mit der Release-Version; `Tools/Check-Version.ps1` prüft sie.

### Nur MCP-Werkzeuge (ein Befehl)

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

Alternativ `atlas/.mcp.json` ins Projekt kopieren (ohne `--root` gilt das Arbeitsverzeichnis). Schreibende Werkzeuge lassen sich mit `mcp.disabledTools` in `atlas.json` oder `--restricted` abschalten.

### Plugin aus dem Repository testen

```
claude plugin validate Editors/ClaudeCode/atlas
claude --plugin-dir Editors/ClaudeCode/atlas
```
