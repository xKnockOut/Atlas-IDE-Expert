# Argus für VS Code

Startet den Server `ArgusServer.exe` automatisch, sobald ein Ordner mit `.dproj` oder `argus.json` oder eine Delphi-Datei geöffnet wird.

## Installieren

`pwsh Tools/Package-VSCode.ps1` baut `argus-<Version>.vsix` mit mitgelieferter EXE; installieren mit `code --install-extension argus-0.2.0.vsix`.

Gesucht wird der Server in dieser Reihenfolge: Einstellung `argus.serverPath`, mitgelieferte EXE, `Output\Win64\Release|Debug\Bin` im Arbeitsbereich, `PATH`.

## Befehle

Server neu starten, Status anzeigen, Projekt kompilieren, Index neu aufbauen, Konfiguration und Plattform wählen (alle unter „Argus:“ in der Befehlspalette).

## Entwickeln

1. Server bauen (Win64, Debug). Er liegt dann unter `Output\Win64\Debug\Bin\ArgusServer.exe`.
2. In diesem Ordner `npm install` und `npm run compile` ausführen.
3. Den Ordner `Editors/VSCode` in VS Code öffnen und mit F5 einen Erweiterungs-Host starten. Darin den Repo-Ordner oder ein Delphi-Projekt öffnen.

## Einstellungen

| Einstellung | Bedeutung |
|---|---|
| `argus.serverPath` | Pfad zu `ArgusServer.exe` |
| `argus.logLevel` | Mindeststufe: `debug`, `info`, `warning`, `error` |
| `argus.logFile` | Optionale Logdatei (`--log`) |
| `argus.traceFile` | Optionaler Mitschnitt aller JSON-Nachrichten (`--trace`) |
| `argus.trace.server` | Nachrichtenaustausch im Ausgabefenster „Argus Trace“ |
| `argus.delphiVersion`, `language`, `project`, `config`, `platform`, `rules`, `exclude` | Wie die gleichnamigen Schlüssel in `argus.json`; die Datei im Projekt hat je Schlüssel Vorrang, bei `rules` je Regel |

Meldungen des Servers (`window/logMessage` und stderr) erscheinen im Ausgabefenster „Argus“. Der Befehl „Argus: Server neu starten“ startet den Server neu, etwa nach einem neuen Build.

Stürzt der Server ab, startet die Erweiterung ihn neu. Nach fünf Abstürzen innerhalb von drei Minuten gibt sie auf und meldet das; dann hilft der Befehl „Server neu starten“.
