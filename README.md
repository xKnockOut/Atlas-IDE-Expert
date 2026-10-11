# Atlas IDE Expert

Experte für RAD Studio (Delphi/Object Pascal): ein IDE-Plugin mit eigener Oberfläche und ein eigener Language Server (LSP), dazu eine MCP-Schnittstelle für Claude Code. Funktionsumfang und Ausbaustufen stehen in den [Issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues); die Epics #130 bis #139 bilden die Ausbaustufen ab.

## Das IDE-Plugin

`Atlas.IDE.Expert` ersetzt in RAD Studio 13 (und 12) die eingebaute Code Insight durch eigene Fenster, die der Atlas-Server mit Daten füllt:

- **Vervollständigung** mit Detailpanel, Filter-Chips, unscharfer Suche, lernender Reihenfolge, Postfix-Vorlagen und Vorschau im Editor
- **Parameter-Hint** mit allen Überladungen und aktivem Parameter
- **Hover-Tooltip** mit Deklaration, Dokumentation, anklickbaren Typen, Vererbungskette, Verlauf und Aktionen (Gehe zu, Verwendungen, Deklaration kopieren, Hilfe)
- **Probleme im Editor**: Syntaxfehler, Regeltreffer und Compilermeldungen als Wellenlinien, im Tooltip und als Liste „Atlas-Probleme“ im Meldungsfenster, projektweit; Markierungen wandern beim Tippen mit
- **Compilerprüfung nach dem Speichern** und Übernahme der Compilermeldungen aus dem Reiter „Build“
- **Klammer- und Blockpaare** farbig nach Tiefe, mit eigenen Blocklinien
- **Befehlspalette** (Strg+Umschalt+P), stilles Neuladen extern geänderter Dateien, Hänger-Wächter mit Protokoll

Installation und Einstellungen: [docs/RAD-Studio.md](docs/RAD-Studio.md). Alle Einstellungen liegen unter *Tools › Optionen › Drittanbieter › Atlas*, auch der Pfad zum Server.

## Benutzerdokumentation

- [Installation](docs/Installation.md) für VS Code, Claude Code, Neovim und andere Editoren
- [Konfiguration](docs/Konfiguration.md) von `atlas.json` (erzeugt aus dem JSON-Schema mit `pwsh Tools/Update-ConfigDoc.ps1`)
- [Prüfregeln](docs/Regeln.md)
- [MCP-Werkzeuge](docs/MCP.md)
- [Benchmark](docs/Benchmark.md) der Leistungs-Zielwerte

## Aufbau

| Projekt | Inhalt |
|---|---|
| `Packages/Atlas.Common` | Package, frei von Windows und VCL |
| `Packages/Atlas.Windows` | Package für Windows-spezifische Funktionen, frei von VCL |
| `Application/AtlasServer` | Der Server (Konsolenprogramm, spricht LSP über stdin/stdout) |
| `Packages/Atlas.IDE.Expert` | Das IDE-Plugin (Designtime-Package, Win32), Schichten `Atlas.Core.*`, `Atlas.UI.*`, `Atlas.IDE.*` |
| `Tests/Atlas.Tests` | DUnitX-Tests |

Details zu Rollen, Benennung und Importregeln: [docs/Architektur.md](docs/Architektur.md).

## Voraussetzungen

- Delphi 12 Athens oder neuer, gebaut wird derzeit mit RAD Studio 13 (Win32 und Win64). Das IDE-Plugin muss mit der Delphi-Version gebaut werden, in der es laufen soll; der Server ist davon unabhängig.
- Das Testprojekt ist nur für Win64 eingerichtet, weil DUnitX in der Starter-Edition nur als Win64-Bibliothek vorliegt
- DUnitX (in RAD Studio enthalten, Umgebungsvariable `$(DUnitX)` der IDE)
- PowerShell für die Prüfskripte

## Bauen

In der IDE `Atlas.groupproj` öffnen und **Alle erstellen**. Die Reihenfolge Common → Windows → Server → IDE-Plugin → Tests ist in der Projektgruppe hinterlegt. Common, Windows und Server müssen für dieselbe Plattform gebaut werden, sonst findet der Server die Units der Packages nicht. Das IDE-Plugin ist nur für Win32 eingerichtet (die IDE ist 32-Bit); ein Gruppenbau für Win64 übersetzt es trotzdem mit und prüft so den Quelltext.

Auf der Kommandozeile (RAD-Studio-Eingabeaufforderung bzw. nach `rsvars.bat`):

```bat
msbuild Atlas.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Die Ausgabe landet in `Output\<Plattform>\<Konfiguration>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

## Testen

```bat
Output\Win64\Debug\Bin\Atlas.Tests.exe --exit:Continue
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

`AtlasServer.exe --clear-cache` löscht alle Index-Caches unter `%LOCALAPPDATA%\Atlas`, die keine laufende Instanz nutzt. Der Ordner wird ohnehin auf 256 MB begrenzt, ältere Caches gehen zuerst.

### Linter-Modus

`AtlasServer.exe --check <Ziel>` prüft ohne Editor. Das Ziel kann eine `.dproj` (Hauptdatei und Units), ein Ordner (alle `.pas`, `.dpr` und `.dpk` darunter) oder eine Datei sein. `atlas.json` im Ordner des Ziels gilt wie im Editor. Fehlt sie, gilt die frühere `delphi-lsp.json` (ebenso `delphi-lsp-baseline.json` für die Baseline).

| Parameter | Bedeutung |
|---|---|
| `--format <Art>` | `text` (Standard, wie Compilermeldungen), `json`, `sarif` (SARIF 2.1.0 für GitHub Code Scanning) |
| `--output <Datei>` | Ergebnis in eine Datei statt auf stdout |
| `--rules <a,b>` | nur diese Regeln, z. B. `syntax` |
| `--units <a,b>` | nur diese Units: Name oder Glob-Muster für Pfade |
| `--min-severity <S>` | `hint`, `info`, `warning`, `error` |
| `--profile <Name>` | Regelprofil (`standard`, `fast`, `strict`, `security`, `style` oder eigenes aus `profiles`); geht `profile` in `atlas.json` vor |
| `--baseline <Datei>` | bekannte Treffer ausblenden; ohne Angabe gilt `atlas-baseline.json` neben `atlas.json`, falls vorhanden. Der Editor blendet sie ebenso aus |
| `--update-baseline` | Baseline aus den aktuellen Treffern neu schreiben (verschwundene Einträge fallen heraus), Exit-Code 0 |
| `--changed [<Basis>]` | nur Dateien, die sich laut Git (bzw. SVN, siehe unten) gegenüber der Merge-Base mit `<Basis>` (Standard `main`) geändert haben; geänderte `.dfm`/`.fmx` prüfen ihre Unit, geänderte `.inc` alle Units, die sie einbinden, geänderte `.dproj`/`.dpk`/`.dpr`/`atlas.json` alles |
| `--diff <Ref>` | wie `--changed`, aber direkt gegenüber `<Ref>` |
| `--include-uncommitted` | mit `--changed`/`--diff` auch Index, Arbeitsverzeichnis und neue Dateien |
| `--changed-lines` | nur Treffer in geänderten Zeilen; zusammen mit der Baseline nur neue Treffer in geänderten Zeilen |
| `--suppression-stats` | statt der Treffer: wie oft jede Regel per `lsp-ignore` unterdrückt wird (häufigste zuerst, mit ungenutzten), als Text oder JSON; Exit-Code 0 |

Exit-Code: 0 ohne Warnungen und Fehler, 1 bei Warnungen, 2 bei Fehlern, 3 bei Aufruf- oder Lesefehlern.

In einer SVN-Arbeitskopie vergleicht `--changed` ohne Basis die Arbeitskopie mit BASE (`svn status`), `--changed <Rev>` und `--diff <Rev>` mit der Revision (`svn diff -r`); `--include-uncommitted` nimmt unversionierte Dateien dazu. Git hat Vorrang, wenn beides vorliegt.

Beispiele für einen Pre-Commit-Hook und eine GitHub Action, die nur Geändertes prüfen, liegen in [docs/Beispiele](docs/Beispiele).

### Prüfregeln

Alle Regeln sind in [docs/Regeln.md](docs/Regeln.md) beschrieben. Einzige Quelle ist der Regelkatalog `Packages/Atlas.Common/Katalog/regelkatalog.json` (englisch) mit der Übersetzung `regelkatalog.de.json`. Nach Änderungen `pwsh Tools/Update-RuleCatalog.ps1` ausführen; die CI prüft mit `-Check`, dass Katalog, Implementierung und Dokumentation übereinstimmen.

## Wichtig: stdout gehört dem Protokoll

Der Server spricht LSP über stdin/stdout. Jede zusätzliche Ausgabe auf stdout (`Writeln`, unbehandelte Exceptions) zerstört die Kommunikation mit dem Editor. Alle Diagnosemeldungen laufen über `ILogger` (`Atlas.Common.Logging`) an `OutputDebugString`, die Logdatei, `window/logMessage` und bei Fehlern stderr. Nach dem Start biegt der Server das stdout-Handle und `Output` auf stderr um, sodass auch Bibliotheken das Protokoll nicht stören können.

## Lizenzen

Atlas steht unter der MIT-Lizenz (`LICENSE`); Drittanbieter-Komponenten mit Lizenztexten stehen in `THIRD-PARTY-NOTICES.md` (erzeugt von `Tools/Update-ThirdPartyNotices.ps1`).

Cache und Benchmark-Korpus bleiben lokal, VCL-Quellen werden nie eingecheckt. Der Index-Cache liegt unter `%LOCALAPPDATA%\Atlas`; RTL- und VCL-Quellen liest der Server nur aus der lokalen Delphi-Installation. `Tools/Check-NoEmbarcaderoSources.ps1` prüft in der CI, dass `Tests/` und die `.vsix` keine Datei mit Embarcadero-Copyright-Kopf enthalten.
