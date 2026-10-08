# Installation

BetterDelphiLSP ist eine einzelne Datei, `BetterDelphiLSP.exe` (Windows, Win64). Sie spricht LSP über stdio, mit `--mcp` MCP für KI-Agenten und mit `--check` prüft sie ohne Editor. Eine installierte RAD-Studio-Version braucht der Server nur für Compiler-Meldungen (`compiler.onSave`); die passende Version liest er aus der `.dproj`.

## Server besorgen

- **Release:** `BetterDelphiLSP.exe` aus dem neuesten [GitHub-Release](https://github.com/xKnockOut/BetterDelphiLSP/releases) laden und in einen Ordner im `PATH` legen.
- **Selbst bauen:** `BetterDelphiLSP.groupproj` in RAD Studio öffnen und Win64 bauen; die EXE liegt unter `Output\Win64\<Config>\Bin\`.

## VS Code

Die Erweiterung `betterdelphilsp-<Version>.vsix` aus dem Release enthält den Server schon:

```
code --install-extension betterdelphilsp-0.1.0.vsix
```

Sie startet, sobald ein Ordner mit `.dproj` oder `delphi-lsp.json` geöffnet wird. Einstellungen und Befehle: [Editors/VSCode/README.md](../Editors/VSCode/README.md).

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

`source.organizeImports` entfernt doppelte Einträge in den uses-Listen; mit `"sortUses": true` in `delphi-lsp.json` werden sie zusätzlich sortiert. `source.fixAll` wendet alle Korrekturen an, die ihre Regel als sicher markiert, z. B. das Entfernen ungenutzter `lsp-ignore`-Kommentare.

## Claude Code

Als MCP-Server (Index-Werkzeuge für den Agenten):

```
claude mcp add delphi -- BetterDelphiLSP.exe --mcp --root C:\Projekte\App
```

Mit Diagnosen und Navigation als Plugin: [Editors/ClaudeCode/README.md](../Editors/ClaudeCode/README.md). Werkzeuge: [MCP.md](MCP.md).

## Neovim

Ab Neovim 0.11: [Editors/Neovim/README.md](../Editors/Neovim/README.md).

## Andere Editoren

Jeder LSP-Client funktioniert mit diesen Angaben:

| Angabe | Wert |
|---|---|
| Befehl | `BetterDelphiLSP.exe` (optional `--log <Datei> --log-level debug`) |
| Transport | stdio |
| Dateitypen | `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm` |
| Sprach-ID | beliebig, üblich `delphi` oder `objectpascal` |
| Wurzel | Ordner mit `.dproj`, `delphi-lsp.json` oder `.git` |

Fertige Beispiele mit Dateizuordnung für `.pas`, `.dpr`, `.dpk` und `.dfm`:

- Helix: [Editors/Helix](../Editors/Helix/README.md)
- Sublime Text (Paket LSP): [Editors/SublimeText](../Editors/SublimeText/README.md)
- Zed (Dev-Erweiterung): [Editors/Zed](../Editors/Zed/README.md)

## Ohne Editor (CI)

```
BetterDelphiLSP.exe --check App.dproj --format sarif --output befunde.sarif
```

Weitere Optionen stehen in der [README](../README.md).

## Weiter

- [Konfiguration.md](Konfiguration.md): alle Schlüssel von `delphi-lsp.json`
- [Regeln.md](Regeln.md): alle Prüfregeln mit Beispielen und Unterdrückung per `// lsp-ignore: <regel>`
