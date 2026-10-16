# Atlas IDE Expert

*English version: [README.md](README.md).*

Experte für RAD Studio (Delphi/Object Pascal): ein IDE-Plugin mit eigener Oberfläche und ein eigener Language Server (LSP), dazu eine MCP-Schnittstelle für Claude Code. Funktionsumfang und Ausbaustufen stehen in den [Issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues); die Epics #130 bis #139 bilden die Ausbaustufen ab.

## Das IDE-Plugin

`Atlas.IDE.Expert` ersetzt in RAD Studio 13 (und 12) die eingebaute Code Insight durch eigene Fenster, die der Atlas-Server mit Daten füllt:

- **Vervollständigung** mit Detailpanel, Filter-Chips, unscharfer Suche, lernender Reihenfolge, Postfix-Vorlagen, Vorschau im Editor, Aufzählungswerten zuerst und Mengenelementen zum Abhaken
- **Parameter-Hint** mit allen Überladungen und aktivem Parameter
- **Hover-Tooltip** mit Deklaration, Dokumentation, anklickbaren Typen, Vererbungskette, Verlauf und Aktionen (Gehe zu, Verwendungen, Deklaration kopieren, Hilfe)
- **Probleme im Editor**: Syntaxfehler, Regeltreffer und Compilermeldungen als Wellenlinien, im Tooltip und als Liste „Atlas-Probleme“ im Meldungsfenster, projektweit; Markierungen wandern beim Tippen mit
- **Compilerprüfung nach dem Speichern** und Übernahme der Compilermeldungen aus dem Reiter „Build“
- **Klammer- und Blockpaare** farbig nach Tiefe, mit eigenen Blocklinien
- **Ergebnisfenster** „Atlas-Ergebnisse“ für Referenzen (auch in Formularen), Implementierungen, Aufrufer, Aufrufe und Vererbung; projektweite Symbolsuche; Vorschau vor dem Umbenennen
- **Code-Aktionen** (Alt+Enter), Auswahl erweitern und verkleinern (Strg+W, Strg+Umschalt+W), Gehe zu Implementierung und Typdefinition, Wechsel zwischen Deklaration und Implementierung (Strg+Umschalt+↑/↓), qualifizierten Namen kopieren; alles auch im Kontextmenü des Editors unter *Atlas*. Schnellbefehle wie `/uses Unit` laufen nach Enter, `///` über einer Deklaration erzeugt den Dokumentationskommentar; Alt+Einfg zeigt im **Erzeugen-Menü**, was sich am Cursor erzeugen lässt (Konstruktor, Properties, überschriebene Methoden, Interface-Methoden, Umschließen, Vorlagen)
- **Formular-Designer**: Offene Formulare gehen im Stand des Designers an den Server, Referenzen, Umbenennen und Prüfungen sehen also ungespeicherte Änderungen; das Umbenennen eines Ereignis-Handlers ändert auch seine Zuordnung im Designer
- **Befehlspalette** (Strg+Umschalt+P), stilles Neuladen extern geänderter Dateien, Hänger-Wächter mit Protokoll

Installation und Einstellungen: [docs/RAD-Studio.md](docs/RAD-Studio.md). Alle Einstellungen liegen unter *Tools › Optionen › Drittanbieter › Atlas*, auch der Pfad zum Server.

## Installation

### IDE-Plugin für RAD Studio 13 und 12

1. Repository klonen und `Atlas.groupproj` in RAD Studio öffnen.
2. `Atlas.Common`, `Atlas.Windows` und `AtlasServer` für **Win64** erzeugen (alle drei für dieselbe Plattform). Ergebnis: `Output\Win64\Debug\Bin\AtlasServer.exe`. Alternativ `AtlasServer.exe` aus einem [Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) nehmen; der Server hängt nicht von der Delphi-Version ab.
3. `Atlas.IDE.Expert` mit der Delphi-Version erzeugen, in der das Plugin laufen soll: für die klassische IDE **Win32**, für die 64-Bit-IDE **Win64**. Ergebnis: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl` (Delphi 13; Delphi 12: `…290.bpl`, 64-Bit-IDE: `Output\Win64\…`).
4. *Komponente › Packages installieren › Hinzufügen* und die BPL auswählen.
5. Liegt der Server nicht unter `Output\…\Bin` oder neben der BPL: *Tools › Optionen › Drittanbieter › Atlas*, Feld „Atlas-Server“. Die Seite zeigt an, ob der Server gefunden wird.
6. Delphi einmal neu starten: Atlas schaltet Help Insight und die Strukturhervorhebung der IDE ab, damit nichts doppelt erscheint; die IDE liest diese Schalter nur beim Start.

Einzelheiten und Fehlersuche: [docs/RAD-Studio.md](docs/RAD-Studio.md).

### Unterstützte Versionen

- RAD Studio bzw. Delphi **13 Florence** und **12 Athens** (ab 12.0). Das Plugin wird mit genau der Version gebaut, in der es läuft; die BPL trägt die Package-Version im Namen (`370` für Delphi 13, `290` für Delphi 12), damit beide nebeneinander liegen können.
- Klassische 32-Bit-IDE (BPL für Win32) und 64-Bit-IDE ab Delphi 12.3 (BPL für Win64).
- Windows 10 und 11.

Gebaut und geprüft wird bisher nur mit RAD Studio 13 in der 32-Bit-IDE. Was ohne Delphi-12-Installation und 64-Bit-IDE noch ungeprüft ist, steht in [docs/RAD-Studio.md](docs/RAD-Studio.md#ungeprüft).

### Claude Code und ohne Editor

- **Claude Code:** MCP-Werkzeuge und LSP als Plugin, siehe [Editors/ClaudeCode](Editors/ClaudeCode/README.md)
- **CI und Kommandozeile:** `AtlasServer.exe --check`, siehe [Linter-Modus](#linter-modus)

Ausführlich: [docs/Installation.md](docs/Installation.md).

## Benutzerdokumentation

- [Installation](docs/Installation.md) für RAD Studio, Claude Code und die Kommandozeile
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

- `server.yml`: Build der Projektgruppe über das IDE-Plugin `cc.ps1` (RAD Studio Starter hat kein msbuild, ADR 0007) für Win64 und Win32, samt Plugin-BPLs `Atlas.IDE.Expert370.bpl` für die klassische und die 64-Bit-IDE (Win32 und Win64, als Artefakte abgelegt), und DUnitX-Tests (nur Win64, ADR 0008). Ergebnisse als Check „DUnitX-Ergebnisse“ im Pull Request.
  - Der Job braucht einen selbst gehosteten Windows-Runner (Labels `self-hosted`, `windows`, `delphi`) auf dem Arbeitsrechner des Entwicklers. Er läuft im angemeldeten Benutzerkontext und nicht als Dienst, weil `cc.ps1` eine IDE startet, und nur, solange dieser Rechner eingeschaltet ist. Jeder Job startet eine eigene Scratch-IDE.
  - Er läuft nur mit der Repository-Variablen `DELPHI_RUNNER=true`; sonst meldet der Job „uebersprungen“ das in der Zusammenfassung des Laufs. `CC_SCRIPT` überschreibt den Pfad zu `cc.ps1`.
  - Ein neuer Push auf denselben Branch bricht den laufenden Build ab (`concurrency`).
- `package-dependencies.yml`: Package-Abhängigkeiten, stdout-Regel, Delphi-12-Verträglichkeit, Regelkatalog, Konfigurationsdoku und keine Embarcadero-Quellen in `Tests/`.

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
| `--fail-on <S>` | ab welchem Treffer der Exit-Code 1 ist: `error` (Standard), `warning` oder `never`. So brechen Warnungen in Altprojekten keinen Pre-Commit-Hook ab |
| `--source-root <Ordner>` | Wurzel der SARIF-Pfade; Standard ist die Git-Wurzel über dem Ziel, sonst der Ordner des Ziels. Pfade darunter tragen `uriBaseId` `%SRCROOT%`, Dateien außerhalb erscheinen als absoluter `file:`-URI |
| `--profile <Name>` | Regelprofil (`standard`, `fast`, `strict`, `security`, `style` oder eigenes aus `profiles`); geht `profile` in `atlas.json` vor |
| `--baseline <Datei>` | bekannte Treffer ausblenden; ohne Angabe gilt `atlas-baseline.json` neben `atlas.json`, falls vorhanden. Der Editor blendet sie ebenso aus |
| `--update-baseline` | Baseline aus den aktuellen Treffern neu schreiben, Exit-Code 0. Auf stderr stehen zuerst die Einträge ohne Datei mit Pfad (umbenannte, verschobene oder gelöschte Dateien; sie fallen heraus), dann die Zähler: Treffer, Dateien, neu, entfernt, unverändert |
| `--changed [<Basis>]` | nur Dateien, die sich laut Git (bzw. SVN, siehe unten) gegenüber der Merge-Base mit `<Basis>` (Standard `main`) geändert haben; geänderte `.dfm`/`.fmx` prüfen ihre Unit, geänderte `.inc` alle Units, die sie einbinden, geänderte `.dproj`/`.dpk`/`.dpr`/`atlas.json` alles |
| `--diff <Ref>` | wie `--changed`, aber direkt gegenüber `<Ref>` |
| `--include-uncommitted` | mit `--changed`/`--diff` auch Index, Arbeitsverzeichnis und neue Dateien |
| `--changed-lines` | nur Treffer in geänderten Zeilen; zusammen mit der Baseline nur neue Treffer in geänderten Zeilen |
| `--suppression-stats` | statt der Treffer: wie oft jede Regel per `lsp-ignore` unterdrückt wird (häufigste zuerst, mit ungenutzten), als Text oder JSON; Exit-Code 0 |
| `--metrics` | statt der Treffer: Code-Metriken je Methode (Länge, Verschachtelungstiefe, zyklomatische und kognitive Komplexität, Parameter; #66) mit den Grenzwerten aus `atlas.json` (`"max"` der Regeln `metric-*`); `--format text` schreibt einen Markdown-Bericht, `json` die Metrikdaten; Exit-Code 0 |
| `--todos` | statt der Treffer: offene TODO-Einträge (#68) aus `// TODO`, `// FIXME` und dem Format der IDE-To-Do-Liste `{ TODO 1 -oPerson -cKategorie : Text }` mit Priorität, Person und Kategorie; weitere Marken über die Option `"keywords"` der Regel `todo-comment`; `--format text` schreibt eine Markdown-Übersicht, `json` die Daten; Exit-Code 0 |

Exit-Code: 1, wenn ein Treffer `--fail-on` erreicht (Standard: mindestens ein Fehler), sonst 0; 3 bei Aufruf- oder Lesefehlern. Treffer aus der Baseline zählen nie.

Baseline (#97): Ein Eintrag in `atlas-baseline.json` merkt sich Datei, Regel, die umgebende Routine (voll qualifiziert wie `TFoo.Bar`, außerhalb einer Routine der Abschnitt wie `implementation`), einen Fingerabdruck der Zeile ohne Leerraum und einen Fingerabdruck des Codes ±2 Zeilen darum. Dieselbe Zeile in einer anderen Routine gilt deshalb als neu, ebenso ein Treffer, der in eine andere Routine wandert. Neu Einrücken, verschobene Zeilen und eine umbenannte Routine (Kontext gleich, alter Name nicht mehr in der Datei) überstehen die Baseline. Eine umbenannte oder verschobene Datei verliert ihre Einträge: Ihre Treffer erscheinen als neu, bis die Baseline aktualisiert ist. Ältere Dateien ohne Routine bleiben lesbar und werden beim nächsten Aktualisieren ergänzt. Unterdrückungskommentare für Treffer aus der Baseline melden kein `unused-suppression`. In Editoren aktualisiert der Befehl `atlas.updateBaseline` (`workspace/executeCommand`, Argument: URI des Projekts oder Ordners) die Baseline und antwortet mit den Zählern; er prüft dafür alle Dateien des Projekts und hält den Server so lange auf. In SARIF trägt jedes Ergebnis `partialFingerprints` (`atlasBaseline/v1` aus Regel, Routine und Zeile, `atlasContext/v1` aus dem Kontext, je mit laufender Nummer `:n` bei gleichen Werten in einer Datei); mit Baseline kommt `baselineState` hinzu: `new`, `unchanged` (als externe Unterdrückung) oder `absent` (Eintrag ohne Treffer). Text, JSON und Exit-Code enthalten nur die neuen Treffer.

In SARIF steht als `message.text` der englische Name der Regel aus dem Katalog, ohne Konfidenz-Zusatz. Die Konfidenz steht in `properties.confidence`, die deutsche Meldung des Treffers in `properties.detail`.

Jeder Regeltreffer hat eine Konfidenz (hoch, mittel, niedrig). Sie begrenzt den Schweregrad, auch wenn `rules` ihn höher einstellt: mittlere Konfidenz höchstens Warnung, niedrige höchstens Hinweis. Treffer unter `minConfidence` (Standard `medium`) bleiben aus. Die Konfidenz steht nie im Meldungstext, sondern als eigene Spalte in der Textausgabe (`[Konfidenz mittel]`), in JSON als `confidence`, im LSP als `data.confidence` und im Tooltip des Plugins als eigene Zeile.

In einer SVN-Arbeitskopie vergleicht `--changed` ohne Basis die Arbeitskopie mit BASE (`svn status`), `--changed <Rev>` und `--diff <Rev>` mit der Revision (`svn diff -r`); `--include-uncommitted` nimmt unversionierte Dateien dazu. Es gilt die nächstliegende Arbeitskopie über dem Ordner der Konfiguration (`.git` oder `.svn`), bei Gleichstand Git; `vcs.provider` in `%APPDATA%\Atlas\settings.json` legt die Art fest (`auto`, `git`, `svn`) oder schaltet ab (`off`). svn muss als Kommandozeilenwerkzeug installiert sein (TortoiseSVN mit Kommandozeilenwerkzeugen genügt).

Beispiele für einen Pre-Commit-Hook und eine GitHub Action, die nur Geändertes prüfen, liegen in [docs/Beispiele](docs/Beispiele).

### Prüfregeln

Alle Regeln sind in [docs/Regeln.md](docs/Regeln.md) beschrieben. Einzige Quelle ist der Regelkatalog `Packages/Atlas.Common/Katalog/regelkatalog.json` (englisch) mit der Übersetzung `regelkatalog.de.json`. Nach Änderungen `pwsh Tools/Update-RuleCatalog.ps1` ausführen; die CI prüft mit `-Check`, dass Katalog, Implementierung und Dokumentation übereinstimmen.

## Wichtig: stdout gehört dem Protokoll

Der Server spricht LSP über stdin/stdout. Jede zusätzliche Ausgabe auf stdout (`Writeln`, unbehandelte Exceptions) zerstört die Kommunikation mit dem Editor. Alle Diagnosemeldungen laufen über `ILogger` (`Atlas.Common.Logging`) an `OutputDebugString`, die Logdatei, `window/logMessage` und bei Fehlern stderr. Nach dem Start biegt der Server das stdout-Handle und `Output` auf stderr um, sodass auch Bibliotheken das Protokoll nicht stören können.

## Lizenzen

Atlas steht unter der MIT-Lizenz (`LICENSE`); Drittanbieter-Komponenten mit Lizenztexten stehen in `THIRD-PARTY-NOTICES.md` (erzeugt von `Tools/Update-ThirdPartyNotices.ps1`).

Cache und Benchmark-Korpus bleiben lokal, VCL-Quellen werden nie eingecheckt. Der Index-Cache liegt unter `%LOCALAPPDATA%\Atlas`; RTL- und VCL-Quellen liest der Server nur aus der lokalen Delphi-Installation. `Tools/Check-NoEmbarcaderoSources.ps1` prüft in der CI, dass `Tests/` keine Datei mit Embarcadero-Copyright-Kopf enthalten.
