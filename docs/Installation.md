# Installation

Argus ist eine einzelne Datei, `ArgusServer.exe` (Windows, Win64). Sie spricht LSP über stdio, mit `--mcp` MCP für KI-Agenten und mit `--check` prüft sie ohne Editor. Eine installierte RAD-Studio-Version braucht der Server nur für Compiler-Meldungen (`compiler.onSave`); die passende Version liest er aus der `.dproj`.

## Server besorgen

- **Release:** `ArgusServer.exe` aus dem neuesten [GitHub-Release](https://github.com/xKnockOut/Argus-IDE-Expert/releases) laden und in einen Ordner im `PATH` legen.
- **Selbst bauen:** `Argus.groupproj` in RAD Studio öffnen und Win64 bauen; die EXE liegt unter `Output\Win64\<Config>\Bin\`.

## VS Code

Die Erweiterung `argus-<Version>.vsix` aus dem Release enthält den Server schon:

```
code --install-extension argus-0.1.0.vsix
```

Sie startet, sobald ein Ordner mit `.dproj` oder `argus.json` geöffnet wird. Einstellungen und Befehle: [Editors/VSCode/README.md](../Editors/VSCode/README.md).

## Claude Code

Als MCP-Server (Index-Werkzeuge für den Agenten):

```
claude mcp add delphi -- ArgusServer.exe --mcp --root C:\Projekte\App
```

Mit Diagnosen und Navigation als Plugin: [Editors/ClaudeCode/README.md](../Editors/ClaudeCode/README.md). Werkzeuge: [MCP.md](MCP.md).

## Neovim

Ab Neovim 0.11: [Editors/Neovim/README.md](../Editors/Neovim/README.md).

## Andere Editoren

Jeder LSP-Client funktioniert mit diesen Angaben:

| Angabe | Wert |
|---|---|
| Befehl | `ArgusServer.exe` (optional `--log <Datei> --log-level debug`) |
| Transport | stdio |
| Dateitypen | `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm` |
| Sprach-ID | beliebig, üblich `delphi` oder `objectpascal` |
| Wurzel | Ordner mit `.dproj`, `argus.json` oder `.git` |

Beispiel für Helix (`languages.toml`):

```toml
[language-server.argus]
command = "ArgusServer.exe"

[[language]]
name = "delphi"
scope = "source.pascal"
file-types = ["pas", "dpr", "dpk", "inc"]
roots = [".dproj", "argus.json"]
language-servers = ["argus"]
```

## Ohne Editor (CI)

```
ArgusServer.exe --check App.dproj --format sarif --output befunde.sarif
```

Weitere Optionen stehen in der [README](../README.md).

## Weiter

- [Konfiguration.md](Konfiguration.md): alle Schlüssel von `argus.json`
- [Regeln.md](Regeln.md): alle Prüfregeln mit Beispielen und Unterdrückung per `// lsp-ignore: <regel>`
