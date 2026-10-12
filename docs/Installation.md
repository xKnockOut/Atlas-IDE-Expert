# Installation

Atlas ist eine einzelne Datei, `AtlasServer.exe` (Windows, Win64). Sie spricht LSP über stdio, mit `--mcp` MCP für KI-Agenten und mit `--check` prüft sie ohne Editor. Eine installierte RAD-Studio-Version braucht der Server nur für Compiler-Meldungen (`compiler.onSave`); die passende Version liest er aus der `.dproj`.

## Server besorgen

- **Release:** `AtlasServer.exe` aus dem neuesten [GitHub-Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) laden und in einen Ordner im `PATH` legen.
- **Selbst bauen:** `Atlas.groupproj` in RAD Studio öffnen und Win64 bauen; die EXE liegt unter `Output\Win64\<Config>\Bin\`.

## RAD Studio

Das Plugin `Atlas.IDE.Expert` bindet den Server in die IDE ein: [RAD-Studio.md](RAD-Studio.md).

## Claude Code

Als MCP-Server (Index-Werkzeuge für den Agenten):

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

Mit Diagnosen und Navigation als Plugin: [Editors/ClaudeCode/README.md](../Editors/ClaudeCode/README.md). Werkzeuge: [MCP.md](MCP.md).

## Ohne Editor (CI)

```
AtlasServer.exe --check App.dproj --format sarif --output befunde.sarif
```

Weitere Optionen stehen in der [README](../README_DE.md).

## Weiter

- [Konfiguration.md](Konfiguration.md): alle Schlüssel von `atlas.json`
- [Regeln.md](Regeln.md): alle Prüfregeln mit Beispielen und Unterdrückung per `// lsp-ignore: <regel>`
