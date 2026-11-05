# Atlas IDE Expert

[![Spenden mit PayPal](https://img.shields.io/badge/Spenden-PayPal-00457C?logo=paypal)](https://www.paypal.com/paypalme/xKnockOut288)

*English version: [README.md](README.md).*

Atlas ist ein Experte für RAD Studio (Delphi/Object Pascal). Er ersetzt die eingebaute Code Insight durch eigene Fenster und ergänzt die IDE um Code-Analyse mit 313 Prüfregeln, Refactorings, Navigation, Formular-Unterstützung, Test- und Debug-Hilfen und eine eigene Willkommensseite. Die Daten liefert der **Atlas-Server**, ein eigener Language Server (LSP), der das Projekt indiziert und auch ohne IDE als Linter oder als MCP-Server für Claude Code läuft.

Funktionsumfang und Ausbaustufen stehen in den [Issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues).

## Schnellstart

Voraussetzung ist RAD Studio bzw. Delphi ab Version 12. Fertige Pakete stehen unter [Releases](https://github.com/xKnockOut/Atlas-IDE-Expert/releases); Die Releases 1.0.0 bis 1.2.0 enthalten das Plugin nur für Delphi 13. Was mit 1.2.0 neu ist, steht im [Changelog](CHANGELOG.md).

**Weg A – Release-Paket von Hand einbinden:**

1. `atlas-ide-expert-<Version>.zip` aus dem Release laden und in einen festen Ordner entpacken, z. B. `%LOCALAPPDATA%\Programs\Atlas`. Delphi vorher schließen.
2. Delphi starten, *Komponente › Packages installieren › Hinzufügen* und `Win32\Atlas.IDE.Base370.bpl` aus diesem Ordner wählen (64-Bit-IDE: `Win64\…`). Den Server `AtlasServer.exe` findet das Plugin eine Ebene über der BPL.
3. Delphi einmal neu starten.

Bis 1.1.0 lag dem Paket der Installer `AtlasSetup.exe` bei; seit 1.2.0 gibt es ihn nicht mehr. Einzelheiten: [docs/Installation.md](docs/Installation.md).

**Weg B – selbst bauen und das Package in der IDE installieren:**

1. Delphi ab 12 installieren und dieses Repository klonen.
2. `Atlas.groupproj` in Delphi öffnen und alle Projekte für **Win64** erstellen (*Alle erstellen*). Für die klassische 32-Bit-IDE zusätzlich `Atlas.IDE.Base` für **Win32** erstellen.
3. In Delphi *Komponente › Packages installieren › Hinzufügen* und die BPL wählen: `Output\Win32\Debug\Bpl\Atlas.IDE.Base370.bpl` für die klassische IDE (Delphi 12: `…290.bpl`), `Output\Win64\Debug\Bpl\…` für die 64-Bit-IDE. Den Server `Output\Win64\Debug\Bin\AtlasServer.exe` findet das Plugin dort von selbst. Ab 2.0 danach aus demselben Ordner jedes Modul-Package hinzufügen, z. B. `Atlas.IDE.Debugger370.bpl` (#1456); das Kern-Package `Atlas.IDE.Base` immer zuerst.
4. Delphi einmal neu starten.

Ausführlich: [Installation](#installation).

## Funktionen

Kurzer Überblick; jede Überschrift führt zur ausführlichen Beschreibung. Mit *(experimentell)* markierte Funktionen sind standardmäßig aus und lassen sich unter *Tools › Optionen › Drittanbieter › Atlas* einschalten, sobald der Hauptschalter „Experimentell“ an ist. Was sich je Version geändert hat: [CHANGELOG](CHANGELOG.md).

### [Schreiben](docs/features/de/Schreiben.md)
- **Vervollständigung** im eigenen Popup mit Detailpanel, unscharfer Suche, Favoriten und `+ Unit` für fehlende uses
- **Vorschläge nach Kontext:** Aufzählungswerte, `case`-Werte, Exception-Klassen nach `raise`, Gerüste für anonyme Methoden
- **Parameter-Hint** mit Wahl der Überladung und Prüfung der `Format`-Platzhalter
- **Vorlagen:** Code-, Postfix- und klassenbezogene Vorlagen, eigene Snippets, Schrägstrich-Befehle wie `/uses` und `/extract`
- **Generieren-Menü** (Alt+Einfg) und Bearbeitungshilfen: umschließen, Zeilen verschieben, Kommentare umschalten, var-Blöcke aufräumen
- **Formatierer** (Strg+Umschalt+Alt+L), auch ohne IDE

### [Verstehen](docs/features/de/Verstehen.md)
- **Hover** mit Deklaration, XMLDoc, Vererbung, Werten von Konstanten und Werten beim Debuggen
- **Typhinweise, Code-Metriken und Rekursionsmarken** im Editor; inaktive `{$IFDEF}`-Zweige abgeblendet
- **Architekturübersicht:** Teilsysteme, zentrale Units, Zyklen, Vergleich mit einem gespeicherten Stand
- **Code-Abfragen** wie `classes where inherits TForm and methods > 40`
- **Hotspots, Aufrufdiagramm, Unit-Beziehungen** und der Weg zwischen zwei Symbolen

### [Navigieren](docs/features/de/Navigieren.md)
- **Gehe zu** Definition, Implementierung und Gegenstück; Navigationsverlauf
- **Brotkrumenleiste, Editorleiste und Atlas-Statusleiste** über und unter dem Editor
- **Schnell öffnen** (Strg+P), Unitsuche (Strg+F12) und Suchleiste mit Ersetzen über Dateien hinweg
- **Ergebnisfenster** für Referenzen, Aufrufer und Implementierungen, dazu Auswirkungen und Datenfluss
- **Lesezeichen, Notizen, Minimap und mitlaufender Kopf**

### [Code-Analyse](docs/features/de/Code-Analyse.md)
- **313 Prüfregeln** schon beim Tippen: 204 Fehler, 99 Code-Smells, 10 Sicherheitsregeln
- **„Compiler vorab“:** Fehler und Warnungen von dcc vor dem Build, mit Schnellkorrekturen
- **Fenster „Atlas-Prüfung“** für Datei, Projekt oder Gruppe, mit Sammelkorrekturen
- **Profile, Konfidenz, Baseline und Unterdrückungen** für gewachsene Projekte
- **Linter für CI** mit Ausgabe als Text, JSON oder SARIF. Alle Regeln: [docs/Regeln.md](docs/Regeln.md)

### [Umbauen und Code-Aktionen](docs/features/de/Umbauen.md)
- **Umbenennen** projektweit samt Formularen, **Signatur ändern**, **sicheres Löschen**
- **Methode extrahieren, Variable einführen, `if` ⇄ `case`** und viele weitere Umwandlungen
- **Klassenaktionen:** Interface implementieren, Interface oder Basisklasse herauslösen, Properties erzeugen
- **uses:** fehlende Units ergänzen, sortieren, ungenutzte entfernen
- **Schnellkorrekturen** für viele Regeln (Alt+Enter) und **Atlas-Änderungen rückgängig** über Dateien hinweg

### [Formulare](docs/features/de/Formulare.md)
- **Ungespeicherter Stand des Designers** zählt für Referenzen, Umbenennen und Prüfungen
- **Prüfungen zwischen Formular und Code** und Property-Regeln für Formulardateien
- **Binäre Formulare** in Textformulare umwandeln

### [Bauen, Testen, Debuggen](docs/features/de/Bauen-Testen-Debuggen.md)
- **Schranke für Hinweise und Warnungen**, Schnellkorrekturen für Compilermeldungen, Wächter für den Release-Build
- **DUnitX-Tests** aus dem Editor, auch **nur die von einer Änderung betroffenen**
- **Debuggen:** Werte im Hover und im Editor, Visualisierer, Auswertungsfenster, gezieltes Hineinspringen
- **Exceptions:** Verlauf, Exception-Leiste, „nur mein Code“, Zugriffsverletzungen erklärt

### [IDE-Komfort](docs/features/de/IDE-Komfort.md)
- **Atlas-Willkommensseite** mit Projekten, Verlauf, Issues und Neuigkeiten
- **Issue-Tracker** (GitHub, YouTrack) und **Versionsverwaltung** (Git, SVN) in der IDE
- **Befehlspalette** (Strg+Umschalt+P), Benachrichtigungen, Serverfenster
- **Robustheit:** Fehler erreichen nie die IDE, sicherer Start, nachspielbare Absturzfälle

### [Einstellungen](docs/features/de/Einstellungen.md)
- **Optionsseite als Baum**, jede Funktion mit eigenem Schalter
- **Modulschalter** für ganze Bereiche wie Debuggen, Tests oder Issue-Tracker
- **Exportieren, Importieren, Profile und Zurücksetzen**
- **Werte fürs Team** in `.atlas` und `atlas.json`
- **Sprache wie die IDE** (Deutsch oder Englisch)

### [Claude Code und MCP](docs/features/de/Claude-Code.md)
- **32 MCP-Werkzeuge** zum Lesen, Prüfen, Bauen, Testen, Umbenennen und Korrigieren von Delphi-Code
- **5 Prompts** als Schrägstrich-Befehle, z. B. Unit-Review oder Commit vorbereiten
- **Hook:** Jede Pascal-Datei, die Claude ändert, wird sofort geprüft

### Geplant

Noch nicht in `main`, als Issues angelegt:

- Weitere Prüfregeln (Unter-Issues von #1086)
- Debuggen (#614) und Designer-Funktionen für spätere Versionen
- Aufteilung des Plugins in `Atlas.IDE.Base` und Modul-Packages (2.0, ADR 0017); Debugger, Lesezeichen (Notizen, Lesezeichen, TODO-Liste), Build-Werkzeuge (Bauen beim Öffnen, Projektaufgaben, Startprofile, Compiler-Schalter), Build-Pipeline (Builds auf Auftrag, Prüfung vor dem Kompilieren, Release-Wächter, Bewertung und Zusammenfassung), Tests (DUnitX-Läufer, Test am Cursor, Code Lens, betroffene Tests), die Designer-Leiste, die Suche (Atlas-Suche, Units suchen, Code-Abfragen) die Analyse (Architektur, Hotspots, Unit-Beziehungen, Weg zwischen Symbolen), die Prüfregeln (Baseline, Compilermeldungen in die Baseline, Eigenschaftsregeln, Sammelkorrektur) und der Issue-Tracker (Issue-Kennungen im Code, Issues in der Zeilenhistorie, Befehle des Trackers, Board und „An Issue anhängen“ in den Menüs, „Issue anlegen“ im Kontextmenü, die Kacheln „Meine Issues“, Sprint und „Testergebnisse“ samt Zugang zum Build-Server; „Issue anlegen“ aus Befunden und Absturzfällen erreicht Base über einen Vertrag; Dateien, Umgebung und Shell nur über die Adapter des Moduls) und die Willkommensseite melden sich als Module über die Verträge an (#1455, siehe Aufbau; die Seiten Issue-Tracker und Willkommensseite im Optionsdialog sind Abschnitte ihrer Module) und liegen in eigenen Packages (#1456)

## Installation

### IDE-Plugin für RAD Studio 13 und 12

1. Repository klonen und `Atlas.groupproj` in RAD Studio öffnen.
2. `Atlas.Text`, `Atlas.Common`, `Atlas.Windows` und `AtlasServer` für **Win64** erzeugen (alle vier für dieselbe Plattform). Ergebnis: `Output\Win64\Debug\Bin\AtlasServer.exe`. Alternativ `AtlasServer.exe` aus einem [Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) nehmen; der Server hängt nicht von der Delphi-Version ab.
3. `Atlas.IDE.Base` mit der Delphi-Version erzeugen, in der das Plugin laufen soll: für die klassische IDE **Win32**, für die 64-Bit-IDE **Win64**. Ergebnis: `Output\Win32\Debug\Bpl\Atlas.IDE.Base370.bpl` (Delphi 13; Delphi 12: `…290.bpl`, 64-Bit-IDE: `Output\Win64\…`).
4. *Komponente › Packages installieren › Hinzufügen* und die BPL auswählen. Ab 2.0 liegen die Verträge zwischen den Modulen im Kern-Package und jedes Modul in einem eigenen Package (`Atlas.IDE.Debugger`, `.Designer`, `.Rules`, `.Tests`, `.Bookmarks`, `.Analysis`, `.Search`, `.Build`, `.BuildPipeline`, `.Tracker`, `.Welcome`, #1456), das gegen das Kern-Package übersetzt: nach `Atlas.IDE.Base` erzeugen und installieren.
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
- **CI und Kommandozeile:** `AtlasServer.exe --check`, siehe [Linter-Modus](docs/features/de/Kommandozeile.md#linter-modus)
- **Claude Code in der Cloud (Linux):** Setup-Skript der Umgebung und SessionStart-Hook legen den Server als `AtlasServer` (und `AtlasServer.exe`) nach `/usr/local/bin`, fertig gebaut aus dem Vorab-Release `cloud-linux` oder mit Free Pascal; Einrichtung in [Editors/ClaudeCode](Editors/ClaudeCode/README.md#in-cloud-sitzungen-linux) ([ADR 0013](docs/adr/0013-linux-bau.md), [Bauen unter Linux](#bauen-unter-linux))

Ausführlich: [docs/Installation.md](docs/Installation.md).

## Benutzerdokumentation

- [Funktionen](#funktionen) im Einzelnen: eine Seite je Bereich unter [docs/features/de](docs/features/de/)
- [Installation](docs/Installation.md) für RAD Studio, Claude Code und die Kommandozeile
- [IDE-Plugin](docs/RAD-Studio.md): alle Funktionen im Einzelnen
- [Einstellungen](docs/Einstellungen.md) des Plugins
- [Konfiguration](docs/Konfiguration.md) von `atlas.json` (erzeugt aus dem JSON-Schema mit `pwsh Tools/Update-ConfigDoc.ps1`)
- [Prüfregeln](docs/Regeln.md) (erzeugt aus dem Regelkatalog mit `pwsh Tools/Update-RuleCatalog.ps1`)
- [MCP-Werkzeuge](docs/MCP.md) und das [Plugin für Claude Code](Editors/ClaudeCode/README.md)
- [Benchmark](docs/Benchmark.md) der Leistungs-Zielwerte

Englisch gibt es dieselben Seiten unter [docs/en](docs/en/) und [docs/features/en](docs/features/en/): [Installation](docs/en/Installation.md), [IDE-Plugin](docs/en/RAD-Studio.md), [Einstellungen](docs/en/Settings.md), [Konfiguration](docs/en/Configuration.md), [Prüfregeln](docs/en/Rules.md), [MCP](docs/en/MCP.md), [Claude Code](Editors/ClaudeCode/README.en.md). Jede Seite verlinkt ihr Gegenstück.

## Aufbau

| Projekt | Inhalt |
|---|---|
| `Packages/Atlas.Text` | Package, nur RTL (frei von Windows und VCL); das IDE-Plugin bindet es als Quelltext ein |
| `Packages/Atlas.Common` | Package, frei von Windows und VCL |
| `Packages/Atlas.Windows` | Package für Windows-spezifische Funktionen, frei von VCL |
| `Packages/Atlas.Linux` | Linux-Gegenstücke der Windows-Adapter des Servers, nur Quelltext, für den Bau mit Free Pascal (ADR 0013) |
| `Application/AtlasServer` | Der Server (Konsolenprogramm, spricht LSP über stdin/stdout) |
| `Packages/Atlas.IDE.Base` | Das IDE-Plugin (Designtime-Package; Win32 für die klassische IDE, Win64 für die 64-Bit-IDE ab Delphi 12.3), Schichten `Atlas.Core.*`, `Atlas.UI.*`, `Atlas.IDE.*` |
| `Tests/Atlas.Tests` | DUnitX-Tests |

Details zu Rollen, Benennung und Importregeln: [docs/Architektur.md](docs/Architektur.md).

Verträge für die Module ab 2.0 (#1455, ADR 0017): `Atlas.Core.Modules.Contract` (Modul, Scope, Registry mit `Provide`/`FindAll` nach Interface-GUID, Änderungsmeldung, Vertragsversion), `Atlas.Core.Modules.Registry` (Modulliste aus Anmeldungen, Abmelden rückwärts über den Scope), `Atlas.Core.Modules.Handshake` (exportierte `AtlasCoreContractVersion`), `Atlas.Core.Settings.Contract` und `Atlas.Core.Settings.Parts` (Einstellungsteile der Module, zentral in Base; Werte fehlender Module bleiben erhalten). Was Module beitragen, sammelt Base über `Atlas.Core.Modules.Contributions` ein (Befehle, Einträge im Atlas-Menü und im Kontextmenü des Editors, Tasten, Hörer für Einstellungen, Thema und Ansichtswechsel, Werte im Hover, Schichten der Rinne, eigene Lesezeichen der Übersichtsleiste); es zählen nur laufende Module (ein ausgeschaltetes trägt nichts bei). Ihre Teile laufen in der Feature-Tabelle (`Atlas.Core.Diagnostics.ModuleHosting`); `Atlas.IDE.Foundation.Host` gibt den Modulen Serversitzung, Serverbefehle im Hintergrund (die Antwort erreicht ein Modul nur, solange es angemeldet ist, `Atlas.Core.Modules.Answer`), Meldungsansicht, Warnungen, Log und Felder im Statusfeld. Module bisher: Debugger (`Atlas.IDE.Debug.Composition`, Id `atlas.debugger`) Lesezeichen (`Atlas.IDE.Bookmarks.Composition`, Id `atlas.bookmarks`: Notizen, benannte und schnelle Lesezeichen, TODO-Liste) und Build-Werkzeuge (`Atlas.IDE.BuildTools.Composition`, Id `atlas.build`; meldet seine Teilnehmer an den Compile-Ereignissen beim Stoppen wieder ab) und Build-Pipeline (`Atlas.IDE.BuildPipeline.Composition`, Id `atlas.buildpipeline`, Schalter `buildPipeline`: Builds auf Auftrag mit MCP-Eingang, Prüfung vor dem Kompilieren, Release-Wächter mit „Release-Build prüfen“, Bewertung und Build-Zusammenfassung; Base reicht ihm Compilermeldungen und Bewertung über `Atlas.Core.Build.Pipeline`, ohne das Modul bewertet Base nur nach dem Compiler; andere Module und die Willkommensseite bauen über `IAtlasBuildJobs` in `Atlas.IDE.Contracts.BuildPipeline`; Compile-Ereignisse, Compilermeldungen, Prüfen nach dem Speichern und die Meldungen des letzten Builds bleiben in Base) und Tests (`Atlas.IDE.Tests.Composition`, Id `atlas.tests`; bewertete Builds erfahren sie über `IAtlasBuildVerdictListener`, Base und andere Module starten Tests über `IAtlasTestRunner`, Startoptionen und vorübergehende Startparameter liegen in Base, `Atlas.IDE.Foundation.StartOptions`) Designer (`Atlas.IDE.Designer.Composition`, Id `atlas.designer`: Designer-Leiste), Suche (`Atlas.IDE.Search.Composition`, Id `atlas.search`; Menüeinträge auch unter Ansicht › Atlas, IDE-Aktionen, die ein Modul übernimmt, zeigt die Tastenkürzel-Übersicht über `IAtlasTakenActions`, Anfragen an den Server über `TAtlasIdeHost.RunRequestAsync`) und Analyse (`Atlas.IDE.Analysis.Composition`, Id `atlas.analysis`: Architektur, Hotspots, Unit-Beziehungen mit dem Feld „interface-Änderung“, Weg zwischen Symbolen; nebenläufige Serverbefehle über `TAtlasIdeHost.RunServerCommandAsync`, die Wegansicht des Ergebnisfensters bleibt in Base) und Prüfregeln (`Atlas.IDE.Rules.Composition`, Id `atlas.rules`, Schalter `ruleChecks`: Baseline-Befehle, Eigenschaftsregeln, Sammelkorrektur in „Atlas-Prüfung“ über `IAtlasBulkFixer`, Baseline aktualisieren für die Einrichtung über `IAtlasBaselineSource` in `Atlas.IDE.Contracts.Rules`; Prüfen, Fenster „Atlas-Prüfung“ und Stand der Baseline-Datei bleiben in Base; die Projekt-Zusammenfassungen pflegt Base, `Atlas.IDE.Projects.Summaries`, auch ohne Willkommensseite; die Module Prüfregeln und Tests schreiben Baseline und Testläufe dort hinein, wer sie zeigt, hört auf `IAtlasProjectSummaryListener`) und die Willkommensseite (`Atlas.IDE.Welcome.Composition`, Id `atlas.welcome`, Schalter `welcome`: die Seite mit allen Bereichen, ihre Befehle und Menüeinträge, „Atlas-Start“ auch unter Ansicht › Atlas; Builds, Tests, Startprofile, Aufgaben und Baseline erreicht sie nur über Verträge, `Atlas.IDE.Welcome.Neighbors`, und zeigt Kacheln anderer Module) und der Issue-Tracker (`Atlas.IDE.Tracker.Composition`, Id `atlas.tracker`, Schalter `issues`: Issue-Kennungen im Code, Issues in der Zeilenhistorie, Befehle des Trackers, Board unter Ansicht › Atlas, „An Issue anhängen“ im Atlas-Menü, „Issue anlegen“ im Kontextmenü und auf seiner Taste; „Meine Issues“, die Sprint-Kachel und „Issue anlegen“ sind Kacheln des Moduls auf der Willkommensseite und in „Atlas-Start“ (`Atlas.IDE.Tracker.Tiles`, über `IAtlasWelcomeTile`), aufgeteilt in Kontext, Dienste, Befehle, Statusfeld, Abfrage sowie Beginnen und Beenden (`Atlas.IDE.Tracker.Issues*`, `Atlas.IDE.Tracker.IssueStart`); Methodenrumpf an einer Zeile und Branch-Namen liegen in Base, `TAtlasMethodToggle.BodyAt`, `Atlas.Core.Vcs.BranchNames`); Menüeinträge gibt es auch ohne Befehl (je Projektaufgabe einer); das Ergebnisfenster zeigt Listen der Module mit Ids (`TAtlasResultsItemList`), der allgemeine Tooltip ist `Atlas.UI.Popup.TitledTip`; Verträge zwischen Modulen liegen im Kern-Package unter `Source/Contracts` (Units `Atlas.IDE.Contracts.*`, `IAtlasDebugReportSource` für die Debug-Notiz beim Anhängen an ein Issue, `IAtlasBuildToolsSource` und `IAtlasTestsSource` für die Willkommensseite).

## Voraussetzungen

- Delphi 12 Athens oder neuer, gebaut wird derzeit mit RAD Studio 13 (Win32 und Win64). Das IDE-Plugin muss mit der Delphi-Version gebaut werden, in der es laufen soll; der Server ist davon unabhängig.
- Das Testprojekt ist nur für Win64 eingerichtet, weil DUnitX in der Starter-Edition nur als Win64-Bibliothek vorliegt
- DUnitX (in RAD Studio enthalten, Umgebungsvariable `$(DUnitX)` der IDE)
- PowerShell für die Prüfskripte

## Bauen

In der IDE `Atlas.groupproj` öffnen und **Alle erstellen**. Die Reihenfolge Text → Common → Windows → Server → IDE-Plugin → Tests ist in der Projektgruppe hinterlegt. Text, Common, Windows und Server müssen für dieselbe Plattform gebaut werden, sonst findet der Server die Units der Packages nicht. Das IDE-Plugin ist für Win32 (klassische IDE) und Win64 (64-Bit-IDE ab Delphi 12.3) eingerichtet; welche BPL die IDE lädt, hängt von der IDE ab ([ADR 0008](docs/adr/0008-plattformen.md)).

Auf der Kommandozeile (RAD-Studio-Eingabeaufforderung bzw. nach `rsvars.bat`):

```bat
msbuild Atlas.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Die Ausgabe landet in `Output\<Plattform>\<Konfiguration>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

### Bauen unter Linux

Nur der Server, nur für Claude-Code-Sitzungen in der Cloud und andere Linux-Rechner ohne Delphi ([ADR 0013](docs/adr/0013-linux-bau.md)):

```bash
Tools/Linux/Build-AtlasServer.sh --install /usr/local/bin
```

Das Skript nimmt zuerst das fertige Programm aus dem Vorab-Release `cloud-linux` (Workflow `linux-server.yml`, Stand von main), wenn es zum Quelltext passt. Sonst holt es Free Pascal trunk in einem festen Stand aus demselben Release oder baut ihn einmalig selbst (etwa 10 Minuten, unter `~/.cache/atlas-fpc`), bereitet den Quelltext mit `Tools/Linux/Convert-ForFpc.py` auf und übersetzt nach `Output/Linux64/Bin/AtlasServer`. Hat sich der Quelltext nicht geändert, baut es nicht neu. Plattform-Adapter liegen in `Packages/Atlas.Linux`, die Auswahl trifft `Shell.Platform`. Der Linux-Bau ersetzt den Delphi-Bau vor dem Merge nicht.

Ohne jede Delphi-Installation nehmen `AtlasServer --check X.dproj` und der Editor die Delphi-Version, die das Projekt erwartet: `delphiVersion`, sonst die zur `<ProjectVersion>` der .dproj, sonst die neueste bekannte. Sie setzt nur `CompilerVersion`, `RTLVersion` und `VERxxx` (keine Bibliothekspfade), damit von `{$IF CompilerVersion >= 36}…{$ELSE}…{$ENDIF}` wie in der IDE nur ein Zweig bleibt (#1321).

## Testen

Die DUnitX-Tests laufen ohne geöffnete IDE, nach dem Bau von `Atlas.Tests` (Win64):

```bat
Tests\Tests.bat              :: Funktionstests ohne Benchmarks
Tests\Tests.bat benchmark    :: nur die Benchmarks (Kategorie Benchmark)
Tests\Tests.bat alle         :: beides
```

Prüfskripte (laufen auch als GitHub Action):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # Packages halten ihre Abhängigkeiten ein, Modulgrenzen aus ADR 0017
pwsh Tools/Test-PackageDependencies.ps1    # Selbsttest der Modulgrenzen mit absichtlichen Verstößen
pwsh Tools/Check-ConsoleOutput.ps1         # kein Write/Writeln auf stdout
pwsh Tools/Check-TestCoverage.ps1          # jede Unit mit Logik hat Tests, jede Testunit läuft
pwsh Tools/Check-WindowHosts.ps1           # Fenster und Editorleisten über die gemeinsamen Hüllen
```

`Tests/DccFaelle` enthält Minimalfälle für die Compilerregeln, je Fall mit der Angabe, ob dcc meldet oder übersetzt. `pwsh Tools/Build-DccFaelle.ps1` baut sie in einer Zweit-IDE über `cc.ps1` (Win32 und Win64) und schreibt die dcc-Meldungen je Fall nach `Output/DccFaelle-Ergebnis.txt`; die Regeln dürfen nicht strenger sein als dieses Ergebnis (#1328).

`Tests/Compilermeldungen` enthält je Warnung, Hinweis und Fehler von dcc, den Delphi 13 gezielt meldet, einen Fall (471 Fälle; Codes ohne Fall stehen mit Grund in `ohne-fall.txt`). `pwsh Tools/Build-Compilermeldungen.ps1 -IdeProfile <Profil> -AtlasServer <exe>` baut jeden Fall einzeln in einer Zweit-IDE (Win32 und Win64) und prüft sie mit `AtlasServer --check`; `python3 Tools/Compare-Compilermeldungen.py` schreibt nach `vergleich.md`, was Atlas erkennt, verpasst oder mit anderem Code meldet. Die Ergebnisse des ersten Laufs mit Delphi 13 liegen in `Tests/Compilermeldungen/Ergebnisse` (Atlas erkennt 211 von 332 Codes; die fehlenden Regeln sind #1369–#1383). Ohne IDE baut `-Dcc` die Fälle mit `dcc32`/`dcc64` der mit `-BdsVersion` gewählten Delphi-Version (`23.0` = Delphi 12), `-ResultFile` legt diesen Lauf getrennt ab (#1383). Stilregeln nennen den Compilercode in der Meldung nur, wo dcc ihn meldet: `unused-assignment` H2077 nur bei nicht verwalteten Typen, `uses-cycle` F2047 nur bei reinen interface-Zyklen (F2092 bei einer Unit, die sich selbst nennt), `xmldoc-mismatch` W1205 bis W1208 nur im interface-Teil und nur für Formen, die dcc ablehnt; der Vergleich zählt diese Regeln nur über den Code in der Meldung. Ein zweiter Lauf mit Delphi 13 und Zusatzfällen (#1383) zeigte: dcc meldet W1009 nicht für Felder und statische Methoden, H2367 (auch mit `-JPHNE`), H2440, H2444, W1071, E2373, E2121 und E2287 für denselben Eintrag zweimal gar nicht und übersetzt in der IDE Zeilen bis 1222 Zeichen; die Regeln nennen diese Codes dort nicht mehr, `exports-invalid` lässt Variablen zu und nennt für Konstanten und Typen E2276, `inline-not-expanded` meldet strict private-Mitglieder nicht mehr. Mit der Community Edition bricht `-Dcc` mit Exit-Code 3 ab, weil `dcc32` dort nur meldet, dass es nicht auf der Kommandozeile übersetzt.

## CI

- `server.yml`: Build der Projektgruppe über das IDE-Plugin `cc.ps1` (RAD Studio Starter hat kein msbuild, ADR 0007) für Win64 und Win32, samt Plugin-BPLs `Atlas.IDE.Base370.bpl` für die klassische und die 64-Bit-IDE (Win32 und Win64, als Artefakte abgelegt), und DUnitX-Tests (nur Win64, ADR 0008). Ergebnisse als Check „DUnitX-Ergebnisse“ im Pull Request.
  - Der Job braucht einen selbst gehosteten Windows-Runner (Labels `self-hosted`, `windows`, `delphi`) auf dem Arbeitsrechner des Entwicklers. Er läuft im angemeldeten Benutzerkontext und nicht als Dienst, weil `cc.ps1` eine IDE startet, und nur, solange dieser Rechner eingeschaltet ist. Jeder Job startet eine eigene Scratch-IDE.
  - Er läuft nur mit der Repository-Variablen `DELPHI_RUNNER=true`; sonst meldet der Job „uebersprungen“ das in der Zusammenfassung des Laufs. `CC_SCRIPT` überschreibt den Pfad zu `cc.ps1`.
  - Ein neuer Push auf denselben Branch bricht den laufenden Build ab (`concurrency`).
- `package-dependencies.yml`: Package-Abhängigkeiten, stdout-Regel, Delphi-12-Verträglichkeit, Regelkatalog, Konfigurationsdoku, keine Embarcadero-Quellen in `Tests/` und Atlas-Fenster und Editorleisten nur über ihre gemeinsamen Hüllen.

## Kommandozeile

Der Server läuft auch ohne Editor: Linter für Pre-Commit-Hooks und CI (`--check`, als Text, JSON oder SARIF), Formatierer (`--format-check`, `--format-write`), Architekturbericht, Code-Abfragen, Hotspots und betroffene Tests. Alle Parameter: [docs/features/de/Kommandozeile.md](docs/features/de/Kommandozeile.md).

## Wichtig: stdout gehört dem Protokoll

Der Server spricht LSP über stdin/stdout. Jede zusätzliche Ausgabe auf stdout (`Writeln`, unbehandelte Exceptions) zerstört die Kommunikation mit dem Editor. Alle Diagnosemeldungen laufen über `ILogger` (`Atlas.Common.Logging`) an `OutputDebugString`, die Logdatei, `window/logMessage` und bei Fehlern stderr. Nach dem Start biegt der Server das stdout-Handle und `Output` auf stderr um, sodass auch Bibliotheken das Protokoll nicht stören können.

## Lizenzen

Atlas steht unter der MIT-Lizenz (`LICENSE`); die Lizenzvereinbarung steht in `EULA.txt` (liegt dem Release-Paket bei); Drittanbieter-Komponenten mit Lizenztexten stehen in `THIRD-PARTY-NOTICES.md` (erzeugt von `Tools/Update-ThirdPartyNotices.ps1`).

Cache und Benchmark-Korpus bleiben lokal, VCL-Quellen werden nie eingecheckt. Der Index-Cache liegt unter `%LOCALAPPDATA%\Atlas`; RTL- und VCL-Quellen liest der Server nur aus der lokalen Delphi-Installation. `Tools/Check-NoEmbarcaderoSources.ps1` prüft in der CI, dass `Tests/` keine Datei mit Embarcadero-Copyright-Kopf enthalten.
