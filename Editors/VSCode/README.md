# BetterDelphiLSP für VS Code (minimal)

Kleine Hülle, die den Server `BetterDelphiLSP.exe` für `.pas`, `.dpr` und `.dpk` startet. Sie dient zum Prüfen der Server-Funktionen in VS Code. Der vollständige Ausbau mit `.vsix` und Befehlen folgt in einem eigenen Issue.

## Ausprobieren

1. Server bauen (Win64, Debug). Er liegt dann unter `Output\Win64\Debug\Bin\BetterDelphiLSP.exe`.
2. In diesem Ordner `npm install` und `npm run compile` ausführen.
3. Den Ordner `Editors/VSCode` in VS Code öffnen und mit F5 einen Erweiterungs-Host starten. Darin den Repo-Ordner oder ein Delphi-Projekt öffnen.

Ohne Einstellung sucht die Erweiterung den Server unter `Output\Win64\Debug\Bin` im ersten Arbeitsbereichsordner.

## Einstellungen

| Einstellung | Bedeutung |
|---|---|
| `betterDelphiLsp.serverPath` | Pfad zu `BetterDelphiLSP.exe` |
| `betterDelphiLsp.logLevel` | Mindeststufe: `debug`, `info`, `warning`, `error` |
| `betterDelphiLsp.logFile` | Optionale Logdatei (`--log`) |
| `betterDelphiLsp.traceFile` | Optionaler Mitschnitt aller JSON-Nachrichten (`--trace`) |
| `betterDelphiLsp.trace.server` | Nachrichtenaustausch im Ausgabefenster „BetterDelphiLSP Trace“ |

Meldungen des Servers (`window/logMessage` und stderr) erscheinen im Ausgabefenster „BetterDelphiLSP“. Der Befehl „BetterDelphiLSP: Server neu starten“ startet den Server neu, etwa nach einem neuen Build.
