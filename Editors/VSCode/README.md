# Argus für VS Code (minimal)

Kleine Hülle, die den Server `ArgusServer.exe` für `.pas`, `.dpr` und `.dpk` startet. Sie dient zum Prüfen der Server-Funktionen in VS Code. Der vollständige Ausbau mit `.vsix` und Befehlen folgt in einem eigenen Issue.

## Ausprobieren

1. Server bauen (Win64, Debug). Er liegt dann unter `Output\Win64\Debug\Bin\ArgusServer.exe`.
2. In diesem Ordner `npm install` und `npm run compile` ausführen.
3. Den Ordner `Editors/VSCode` in VS Code öffnen und mit F5 einen Erweiterungs-Host starten. Darin den Repo-Ordner oder ein Delphi-Projekt öffnen.

Ohne Einstellung sucht die Erweiterung den Server unter `Output\Win64\Debug\Bin` im ersten Arbeitsbereichsordner.

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
