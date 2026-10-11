# Installation

Atlas ist eine einzelne Datei, `AtlasServer.exe` (Windows, Win64). Sie spricht LSP über stdio, mit `--mcp` MCP für KI-Agenten und mit `--check` prüft sie ohne Editor. Eine installierte RAD-Studio-Version braucht der Server nur für Compiler-Meldungen (`compiler.onSave`); die passende Version liest er aus der `.dproj`.

## Server besorgen

- **Release:** `AtlasServer.exe` aus dem neuesten [GitHub-Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) laden und in einen Ordner im `PATH` legen.
- **Selbst bauen:** `Atlas.groupproj` in RAD Studio öffnen und Win64 bauen; die EXE liegt unter `Output\Win64\<Config>\Bin\`.

## VS Code

Die Erweiterung `atlas-<Version>.vsix` aus dem Release enthält den Server schon:

```
code --install-extension atlas-0.1.0.vsix
```

Sie startet, sobald ein Ordner mit `.dproj` oder `atlas.json` geöffnet wird. Einstellungen und Befehle: [Editors/VSCode/README.md](../Editors/VSCode/README.md).

### Beim Speichern aufräumen

In der `settings.json` von VS Code:

```json
"[objectpascal]": {
  "editor.codeActionsOnSave": {
    "source.organizeImports": "explicit",
    "source.fixAll": "explicit"
  }
}
```

`source.organizeImports` entfernt doppelte Einträge in den uses-Listen; mit `"sortUses": true` in `atlas.json` werden sie zusätzlich sortiert. `source.fixAll` wendet alle Korrekturen an, die ihre Regel als sicher markiert, z. B. das Entfernen ungenutzter `lsp-ignore`-Kommentare.

## Claude Code

Als MCP-Server (Index-Werkzeuge für den Agenten):

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

Mit Diagnosen und Navigation als Plugin: [Editors/ClaudeCode/README.md](../Editors/ClaudeCode/README.md). Werkzeuge: [MCP.md](MCP.md).

## Neovim

Ab Neovim 0.11: [Editors/Neovim/README.md](../Editors/Neovim/README.md).

## Andere Editoren

Jeder LSP-Client funktioniert mit diesen Angaben:

| Angabe | Wert |
|---|---|
| Befehl | `AtlasServer.exe` (optional `--log <Datei> --log-level debug`) |
| Transport | stdio |
| Dateitypen | `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm` |
| Sprach-ID | beliebig, üblich `delphi` oder `objectpascal` |
| Wurzel | Ordner mit `.dproj`, `atlas.json` oder `.git` |

Beispiel für Helix (`languages.toml`):

```toml
[language-server.atlas]
command = "AtlasServer.exe"

[[language]]
name = "delphi"
scope = "source.pascal"
file-types = ["pas", "dpr", "dpk", "inc"]
roots = [".dproj", "atlas.json"]
language-servers = ["atlas"]
```

## Ohne Editor (CI)

```
AtlasServer.exe --check App.dproj --format sarif --output befunde.sarif
```

Weitere Optionen stehen in der [README](../README_DE.md).

## Weiter

- [Konfiguration.md](Konfiguration.md): alle Schlüssel von `atlas.json`
- [Regeln.md](Regeln.md): alle Prüfregeln mit Beispielen und Unterdrückung per `// lsp-ignore: <regel>`
