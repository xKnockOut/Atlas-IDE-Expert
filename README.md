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

- Delphi 12 Athens (Win32 und Win64)
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
Output\Win32\Debug\Bin\BDLsp.Tests.exe --exit:Continue
```

Package-Abhängigkeiten prüfen:

```powershell
pwsh Tools/Check-PackageDependencies.ps1
```

## Wichtig: stdout gehört dem Protokoll

Der Server spricht LSP über stdin/stdout. Jede zusätzliche Ausgabe auf stdout (`Writeln`, unbehandelte Exceptions) zerstört die Kommunikation mit dem Editor. Diagnosemeldungen laufen über `TDebugOutput` (`OutputDebugString`), später über das zentrale Logging (#3).
