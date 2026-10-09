# Argus IDE Expert

Experte für RAD Studio mit eigenem Language Server (LSP) für Delphi/Object Pascal, mit zusätzlicher MCP-Schnittstelle für Claude Code. Funktionsumfang und Ausbaustufen stehen in den [Issues](https://github.com/xKnockOut/Argus-IDE-Expert/issues); die Epics #130 bis #139 bilden die Ausbaustufen ab.

## Benutzerdokumentation

- [Installation](docs/Installation.md) für VS Code, Claude Code, Neovim und andere Editoren
- [Konfiguration](docs/Konfiguration.md) von `argus.json` (erzeugt aus dem JSON-Schema mit `pwsh Tools/Update-ConfigDoc.ps1`)
- [Prüfregeln](docs/Regeln.md)
- [MCP-Werkzeuge](docs/MCP.md)
- [Benchmark](docs/Benchmark.md) der Leistungs-Zielwerte

## Aufbau

| Projekt | Inhalt |
|---|---|
| `Packages/Argus.Common` | Package, frei von Windows und VCL |
| `Packages/Argus.Windows` | Package für Windows-spezifische Funktionen, frei von VCL |
| `Application/ArgusServer` | Die Anwendung (Konsolenprogramm, spricht LSP über stdin/stdout) |
| `Tests/Argus.Tests` | DUnitX-Tests |

Details zu Rollen, Benennung und Importregeln: [docs/Architektur.md](docs/Architektur.md).

## Voraussetzungen

- Delphi 12 Athens oder neuer, gebaut wird derzeit mit RAD Studio 13 (Win32 und Win64)
- Das Testprojekt ist nur für Win64 eingerichtet, weil DUnitX in der Starter-Edition nur als Win64-Bibliothek vorliegt
- DUnitX (in RAD Studio enthalten, Umgebungsvariable `$(DUnitX)` der IDE)
- PowerShell für die Prüfskripte

## Bauen

In der IDE `Argus.groupproj` öffnen und **Alle erstellen**. Die Reihenfolge Common → Windows → Anwendung → IDE-Plugin → Tests ist in der Projektgruppe hinterlegt. Das IDE-Plugin ist nur für Win32 eingerichtet (die IDE ist 32-Bit); ein Gruppenbau für Win64 übersetzt es trotzdem mit und prüft so den Quelltext.

Auf der Kommandozeile (RAD-Studio-Eingabeaufforderung bzw. nach `rsvars.bat`):

```bat
msbuild Argus.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Die Ausgabe landet in `Output\<Plattform>\<Konfiguration>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

## Testen

```bat
Output\Win64\Debug\Bin\Argus.Tests.exe --exit:Continue
```

Prüfskripte (laufen auch als GitHub Action):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # Packages halten ihre Abhängigkeiten ein
pwsh Tools/Check-ConsoleOutput.ps1         # kein Write/Writeln auf stdout
```

## CI

- `vscode-erweiterung.yml`: Typprüfung, Build und `.vsix` als Artefakt auf einem gehosteten Ubuntu-Runner.
- `server.yml`: Build der Projektgruppe über das IDE-Plugin `cc.ps1` (RAD Studio Starter hat kein msbuild) und DUnitX-Tests auf einem selbst gehosteten Windows-Runner (Labels `self-hosted`, `windows`, `delphi`, im angemeldeten Benutzerkontext). Läuft nur mit Repository-Variable `DELPHI_RUNNER=true`; `CC_SCRIPT` überschreibt den Pfad zu `cc.ps1`. Ergebnisse als Check „DUnitX-Ergebnisse“ im Pull Request.
- `package-dependencies.yml`: Package-Abhängigkeiten und stdout-Regel.

## Kommandozeile

| Parameter | Bedeutung |
|---|---|
| `--log <Datei>` | Logdatei, wird fortgeschrieben |
| `--log-level <Stufe>` | `debug`, `info` (Standard), `warning`, `error`; gilt für Logdatei und `window/logMessage` |
| `--trace <Datei>` | Mitschnitt aller JSON-Nachrichten (`-->` empfangen, `<--` gesendet) |

Werte gehen auch mit `=` (`--log=server.log`). `--stdio` und `--clientProcessId`, die Editoren anhängen, werden ignoriert.

`ArgusServer.exe --clear-cache` löscht alle Index-Caches unter `%LOCALAPPDATA%\Argus`, die keine laufende Instanz nutzt. Der Ordner wird ohnehin auf 256 MB begrenzt, ältere Caches gehen zuerst.

### Linter-Modus

`ArgusServer.exe --check <Ziel>` prüft ohne Editor. Das Ziel kann eine `.dproj` (Hauptdatei und Units), ein Ordner (alle `.pas`, `.dpr` und `.dpk` darunter) oder eine Datei sein. `argus.json` im Ordner des Ziels gilt wie im Editor. Fehlt sie, gilt die frühere `delphi-lsp.json` (ebenso `delphi-lsp-baseline.json` für die Baseline).

| Parameter | Bedeutung |
|---|---|
| `--format <Art>` | `text` (Standard, wie Compilermeldungen), `json`, `sarif` (SARIF 2.1.0 für GitHub Code Scanning) |
| `--output <Datei>` | Ergebnis in eine Datei statt auf stdout |
| `--rules <a,b>` | nur diese Regeln, z. B. `syntax` |
| `--units <a,b>` | nur diese Units: Name oder Glob-Muster für Pfade |
| `--min-severity <S>` | `hint`, `info`, `warning`, `error` |
| `--baseline <Datei>` | bekannte Treffer ausblenden; ohne Angabe gilt `argus-baseline.json` neben `argus.json`, falls vorhanden. Der Editor blendet sie ebenso aus |
| `--update-baseline` | Baseline aus den aktuellen Treffern neu schreiben (verschwundene Einträge fallen heraus), Exit-Code 0 |
| `--suppression-stats` | statt der Treffer: wie oft jede Regel per `lsp-ignore` unterdrückt wird (häufigste zuerst, mit ungenutzten), als Text oder JSON; Exit-Code 0 |

Exit-Code: 0 ohne Warnungen und Fehler, 1 bei Warnungen, 2 bei Fehlern, 3 bei Aufruf- oder Lesefehlern.

### Prüfregeln

Alle Regeln sind in [docs/Regeln.md](docs/Regeln.md) beschrieben. Einzige Quelle ist der Regelkatalog `Packages/Argus.Common/Katalog/regelkatalog.json` (englisch) mit der Übersetzung `regelkatalog.de.json`. Nach Änderungen `pwsh Tools/Update-RuleCatalog.ps1` ausführen; die CI prüft mit `-Check`, dass Katalog, Implementierung und Dokumentation übereinstimmen.

## Wichtig: stdout gehört dem Protokoll

Der Server spricht LSP über stdin/stdout. Jede zusätzliche Ausgabe auf stdout (`Writeln`, unbehandelte Exceptions) zerstört die Kommunikation mit dem Editor. Alle Diagnosemeldungen laufen über `ILogger` (`Argus.Common.Logging`) an `OutputDebugString`, die Logdatei, `window/logMessage` und bei Fehlern stderr. Nach dem Start biegt der Server das stdout-Handle und `Output` auf stderr um, sodass auch Bibliotheken das Protokoll nicht stören können.
