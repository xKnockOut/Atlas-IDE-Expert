# BetterDelphiLSP

Eigener Language Server (LSP) für Delphi/Object Pascal, mit zusätzlicher MCP-Schnittstelle für Claude Code. Funktionsumfang und Ausbaustufen stehen in den [Issues](https://github.com/xKnockOut/BetterDelphiLSP/issues); die Epics #130 bis #139 bilden die Ausbaustufen ab.

## Aufbau

| Projekt | Inhalt |
|---|---|
| `Packages/BDLsp.Common` | Package, frei von Windows und VCL |
| `Packages/BDLsp.Windows` | Package für Windows-spezifische Funktionen, frei von VCL |
| `Application/BetterDelphiLSP` | Die Anwendung (Konsolenprogramm, spricht LSP über stdin/stdout) |
| `Tests/BDLsp.Tests` | DUnitX-Tests |

Details zu Rollen, Benennung und Importregeln: [docs/Architektur.md](docs/Architektur.md).

## Voraussetzungen

- Delphi 12 Athens oder neuer, gebaut wird derzeit mit RAD Studio 13 (Win32 und Win64)
- Das Testprojekt ist nur für Win64 eingerichtet, weil DUnitX in der Starter-Edition nur als Win64-Bibliothek vorliegt
- DUnitX (in RAD Studio enthalten, Umgebungsvariable `$(DUnitX)` der IDE)
- PowerShell für die Prüfskripte

## Bauen

In der IDE `BetterDelphiLSP.groupproj` öffnen und **Alle erstellen**. Die Reihenfolge Common → Windows → Anwendung → Tests ist in der Projektgruppe hinterlegt.

Auf der Kommandozeile (RAD-Studio-Eingabeaufforderung bzw. nach `rsvars.bat`):

```bat
msbuild BetterDelphiLSP.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Die Ausgabe landet in `Output\<Plattform>\<Konfiguration>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

## Testen

```bat
Output\Win64\Debug\Bin\BDLsp.Tests.exe --exit:Continue
```

Prüfskripte (laufen auch als GitHub Action):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # Packages halten ihre Abhängigkeiten ein
pwsh Tools/Check-ConsoleOutput.ps1         # kein Write/Writeln auf stdout
```

## CI

- `vscode-erweiterung.yml`: Typprüfung, Build und `.vsix` als Artefakt auf einem gehosteten Ubuntu-Runner.
- `server.yml`: Build der Projektgruppe und DUnitX-Tests auf einem selbst gehosteten Windows-Runner mit Delphi (Labels `self-hosted`, `windows`, `delphi`). Der Job läuft nur, wenn die Repository-Variable `DELPHI_RUNNER` auf `true` steht. `RADSTUDIO_BIN` überschreibt den Pfad zu `rsvars.bat`. Die Ergebnisse erscheinen als Check „DUnitX-Ergebnisse“ im Pull Request.
- `package-dependencies.yml`: Package-Abhängigkeiten und stdout-Regel.

## Kommandozeile

| Parameter | Bedeutung |
|---|---|
| `--log <Datei>` | Logdatei, wird fortgeschrieben |
| `--log-level <Stufe>` | `debug`, `info` (Standard), `warning`, `error`; gilt für Logdatei und `window/logMessage` |
| `--trace <Datei>` | Mitschnitt aller JSON-Nachrichten (`-->` empfangen, `<--` gesendet) |

Werte gehen auch mit `=` (`--log=server.log`). `--stdio` und `--clientProcessId`, die Editoren anhängen, werden ignoriert.

## Wichtig: stdout gehört dem Protokoll

Der Server spricht LSP über stdin/stdout. Jede zusätzliche Ausgabe auf stdout (`Writeln`, unbehandelte Exceptions) zerstört die Kommunikation mit dem Editor. Alle Diagnosemeldungen laufen über `ILogger` (`BDLsp.Common.Logging`) an `OutputDebugString`, die Logdatei, `window/logMessage` und bei Fehlern stderr. Nach dem Start biegt der Server das stdout-Handle und `Output` auf stderr um, sodass auch Bibliotheken das Protokoll nicht stören können.
