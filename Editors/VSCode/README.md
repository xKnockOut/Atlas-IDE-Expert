# Atlas für VS Code

Startet den Server `AtlasServer.exe` automatisch, sobald ein Ordner mit `.dproj` oder `atlas.json` oder eine Delphi-Datei geöffnet wird.

## Installieren

`pwsh Tools/Package-VSCode.ps1` baut `atlas-<Version>.vsix` mit mitgelieferter EXE; installieren mit `code --install-extension atlas-0.1.0.vsix`.

Gesucht wird der Server in dieser Reihenfolge: Einstellung `atlas.serverPath`, mitgelieferte EXE, `Output\Win64\Release|Debug\Bin` im Arbeitsbereich, `PATH`.

## Befehle

Server neu starten, Status anzeigen, Projekt kompilieren, Index neu aufbauen, Konfiguration und Plattform wählen, qualifizierten Namen kopieren (auch mit Parametertypen; alle unter „Atlas:“ in der Befehlspalette). „Qualifizierten Namen kopieren“ steht auch im Kontextmenü des Editors. „String-Literal als Klartext kopieren“ und „Klartext als String-Literal einfügen“ wandeln Text aus der Zwischenablage um (Einstellungen unter `stringLiteral`).

## Entwickeln

1. Server bauen (Win64, Debug). Er liegt dann unter `Output\Win64\Debug\Bin\AtlasServer.exe`.
2. In diesem Ordner `npm install` und `npm run compile` ausführen.
3. Den Ordner `Editors/VSCode` in VS Code öffnen und mit F5 einen Erweiterungs-Host starten. Darin den Repo-Ordner oder ein Delphi-Projekt öffnen.

## Nicht vertrauenswürdige Ordner

In einem Ordner, dem VS Code nicht vertraut (Workspace Trust), läuft der Server mit `--restricted`:
- Navigation, Hover, Prüfregeln und Formatierung bleiben aktiv.
- Der Compiler (`compiler.onSave`, „Projekt kompilieren“) startet nicht, weil Build-Events Code aus dem Projekt ausführen können.
- `atlas.serverPath` aus den Arbeitsbereichseinstellungen und Server-Programme im Ordner selbst werden ignoriert.

Sobald der Ordner vertraut wird, startet der Server ohne Einschränkung neu.

## Einstellungen

| Einstellung | Bedeutung |
|---|---|
| `atlas.serverPath` | Pfad zu `AtlasServer.exe` |
| `atlas.logLevel` | Mindeststufe: `debug`, `info`, `warning`, `error` |
| `atlas.logFile` | Optionale Logdatei (`--log`) |
| `atlas.traceFile` | Optionaler Mitschnitt aller JSON-Nachrichten (`--trace`) |
| `atlas.trace.server` | Nachrichtenaustausch im Ausgabefenster „Atlas Trace“ |
| `atlas.delphiVersion`, `language`, `project`, `config`, `platform`, `rules`, `exclude` | Wie die gleichnamigen Schlüssel in `atlas.json`; die Datei im Projekt hat je Schlüssel Vorrang, bei `rules` je Regel |

Meldungen des Servers (`window/logMessage` und stderr) erscheinen im Ausgabefenster „Atlas“. Der Befehl „Atlas: Server neu starten“ startet den Server neu, etwa nach einem neuen Build.

Stürzt der Server ab, startet die Erweiterung ihn neu. Nach fünf Abstürzen innerhalb von drei Minuten gibt sie auf und meldet das; dann hilft der Befehl „Server neu starten“.
