# Architektur von Atlas IDE Expert

Gebaut wird mit dem Kommandozeilen-Compiler oder ohne ihn über `Tools/Build-Ide.ps1` (eigene Bau-IDE im
Registry-Profil `AtlasBuild` mit fester Plugin-Kopie über `-Setup`) bzw. das MCP-Werkzeug `build_project` einer
laufenden RAD Studio mit Atlas; welches Projekt für welche Plattform übersetzt und getestet wird, steht in der Projektgruppe
`Atlas.groupproj` und in `Tools/Build-Test.ps1` (Projektgruppe für Win64, mit `-Win32` zusätzlich die Plugin-BPL für die klassische IDE).
Schichten, Threading-Modell, Symbolindex und Cache-Format stehen in den gleichnamigen Abschnitten unten.

Der Schnitt folgt Rollen (Platform-Package, Host, Hosted-Feature; innerhalb eines Features Contract, Internals, Providers, Adapters, Composition, Hosting). Alle Regeln, die daraus für dieses Projekt gelten, stehen in diesem Dokument; `Tools/Check-PackageDependencies.ps1` prüft sie.

## Ausgabeartefakte

| Projekt | Art | Darf verwenden | Darf nicht verwenden |
|---|---|---|---|
| `Atlas.Text` | Platform-Package, zusätzlich als Quelltext im Plugin | nur RTL (`System.*`) | Windows, VCL, FMX, alle anderen Atlas-Artefakte |
| `Atlas.WinBase` | Platform-Package, zusätzlich als Quelltext im Plugin; Gegenstück zu `Atlas.Text` für Code mit Windows-API, den Server und Plugin gleich brauchen (Prozessstart mit Handle-Liste, Lesen mit geteiltem Löschen) | RTL, `Winapi.*`, `System.Win.*`, `Atlas.Text` | VCL, FMX, `Atlas.Common`, `Atlas.Windows`, alles aus dem Plugin |
| `Atlas.Common` | Platform-Package, derzeit zugleich Fachcode-Package des Servers (siehe [Ausnahme](#ausnahme-atlascommon-als-fachcode-package-des-servers)) | plattformunabhängige RTL (`System.*`), `Atlas.Text` | Windows (`Winapi.*`, `System.Win.*`), VCL, FMX, `Atlas.Windows` |
| `Atlas.Windows` | Platform-Package | RTL, `Winapi.*`, `System.Win.*`, `Atlas.Common`, `Atlas.WinBase` | VCL, FMX |
| `Atlas.Linux` | Platform-Package nur als Quelltext für den Linux-Bau des Servers mit Free Pascal (#1109); kein `.dpk` | RTL, FPC-Units für Linux (`BaseUnix`, `Process`, `Pipes`), `Atlas.Common` | Windows, VCL, FMX, `Atlas.Windows` |
| `AtlasServer` | Anwendung (Host) | beide Packages, RTL, Windows, unter Linux `Atlas.Linux` statt `Atlas.Windows` (nur in `Platform.Server`); die Versionsverwaltung des Plugins (`Atlas.Core.VersionControl.*`, #571) als Quelltext | VCL (Konsolenanwendung) |
| `AtlasUpdate` | Anwendung (Host) für Installation und Updates (#1519); Shell in `Application/Source/Shell/Shell.Update*.pas`, Logik in `Atlas.Common.Updates.*`, Adapter in `Atlas.Windows.Updates.Adapters.*` | `Atlas.Text`, `Atlas.Common`, `Atlas.Windows`, RTL, Windows | VCL (Konsolenanwendung) |
| `AtlasMonitor` | Anwendung (Host) mit Fenster (#1901): alle laufenden Server aus ihren Statusdateien, Symbol im Infobereich; Reiter „Prüfen“ (#1900) startet je Ziel einen unsichtbaren Kindprozess von AtlasServer in einem Job mit „beim Schließen beenden“ und liest SARIF bzw. Text/HTML zurück; Shell in `Application/Source/Shell/Shell.Monitor*.pas`, Logik in `Atlas.Common.Monitor.*`, Prozesse und System in `Atlas.Windows.Monitor.*` | `Atlas.Text`, `Atlas.Common`, `Atlas.Windows`, RTL, Windows, VCL (nur in der Shell) | FMX |
| `Atlas.IDE.Base` | Design-Time-Package für RAD Studio (Win32 und Win64) | RTL, `Winapi.*`, `System.Win.*`, VCL, `vclwinx` (Bildsammlung für das Atlas-Symbol, #751), `designide` (Open Tools API), `Atlas.Text.*` und `Atlas.WinBase.*` als Quelltext (`contains … in '..\Atlas.Text\…'` bzw. `'..\Atlas.WinBase\…'`) | `Atlas.Common`, `Atlas.Windows` (eigenständig, damit die IDE nur ein BPL laden muss) |
| `Atlas.Tests` | Testprojekt (DUnitX) | alles, was getestet wird | – |

Abhängigkeitsrichtung:

```text
AtlasServer ──► Atlas.Windows ──► Atlas.Common ──► Atlas.Text ──► RTL
     │               │                 ▲               ▲
     │               └──► Atlas.WinBase ───────────────┘
     └─────────────────────────────────┘
Atlas.IDE.Base ··► Atlas.Text, Atlas.WinBase (Quelltext, kein requires)
```

Die Regeln für die Packages prüft `Tools/Check-PackageDependencies.ps1` (uses-, requires- und contains-Klauseln). Das Skript läuft lokal und in der GitHub Action „Package-Abhängigkeiten“. Zu Atlas.Text und Atlas.WinBase prüft es zusätzlich:

- Das Plugin enthält genau die Units aus `Atlas.Text.dpk` und `Atlas.WinBase.dpk` (sonst W1033) und außer eigenen Units nur solche aus `..\Atlas.Text\Source` und `..\Atlas.WinBase\Source`.
- `Atlas.Tests.dpr` und `AtlasServer.dpr` binden beide nicht als Quelltext ein; sie linken die DCUs aus `Dcu/Atlas.Text` bzw. `Dcu/Atlas.WinBase`.
- **Prozessstart:** Kindprozesse startet nur `TAtlasProcessLauncher` (`Atlas.WinBase.Process`). Er vererbt über `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` genau die Standard-Handles des Kindes; Pipes und Dateien legen die Aufrufer nicht vererbbar an. `forbidden-symbol` in `atlas.json` sperrt `CreateProcess` außerhalb dieser Unit.
- **Kopien-Sperre:** Außerhalb von `Packages/Atlas.Text` entsteht keine neue Routine wie `LineBreakOf`, `SplitLines`, `IndentOf`, `IsWordChar`, `IsIdentChar`, `IsUtf8`, `PercentDecode` oder `DecodeEntities`. Ausnahmen (Fassaden mit eigenem Typ, öffentliche Weiterleitungen, SQL-Bezeichner, Block Rules) stehen mit Grund in `$AllowedLocal`; die Liste soll nur schrumpfen.
- **Kopien-Sperre JSON:** JSON-Lesehelfer (`TextOf`, `StringOf`, `NumberOf`, `IntOf`, `FlagOf`, `ObjectOf`, `ArrayOf` usw. mit einem `TJSONObject` und einem Namen) gibt es nur als `TJsonRead` in `Atlas.Text.Json`: nachsichtig, `nil`, fehlender Wert, `null` und falscher Typ geben die Vorgabe, Ganzzahlen auch aus `12.0` und `"12"`. Ausnahmen mit eigenem Verhalten stehen mit Grund in `$AllowedJsonLocal`.

### Ausnahme: Atlas.Common als Fachcode-Package des Servers

Nach der Rollenregel enthält ein Platform-Package nur technische Abstraktionen; der Fachcode des Servers
(LSP-Methoden in `Lsp`, Prüfregeln in `Rules`, Refactoring- und Schnellbefehle in `Editing`,
Namensauflösung in `Semantics`, MCP-Werkzeuge in `Mcp`) gehörte als Hosted-Features in die Anwendung
Er liegt bewusst weiter in `Atlas.Common`:

- Die Verschiebung beträfe rund 300 Dateien mit Tests, jede `uses`-Klausel, alle Projektdateien und
  `Check-PackageDependencies.ps1`. Ohne Compiler in der Cloud fällt jeder vergessene Import erst
  lokal auf, und jeder parallele Branch an `Lsp`, `Rules` oder `Editing` bekäme Konflikte, die Git
  nicht als Umbenennung erkennt.
- Die Abhängigkeitsregeln gelten trotzdem: `Atlas.Common` bleibt frei von Windows und VCL, die
  Rollenmatrix wird geprüft, und zwischen den Fach-Features gilt eine feste Richtung (unten).

Bedingungen für den späteren Umzug nach `Application/Source/Features/<Feature>/`: der Rollen-Checker
läuft in der CI, und der Umzug geschieht
lokal mit Compiler als rein mechanischer Commit je Feature (zuerst Namenspräfix, dann `git mv`).

Featurerichtung zwischen den Fach-Features: `Lsp`, `Rules`, `Editing` und `Mcp` werden Hosted-Features und
verwenden einander nie (`Atlas.Common: Lsp | Rules | Editing | Mcp`). `Semantics` bleibt Platform-Feature in
`Atlas.Common`; Platform-Features verwenden nie ein Hosted-Feature (`Atlas.Common: Semantics < Lsp` usw.), Hosted-
Features dürfen `Semantics` verwenden. Was zwei Hosted-Features teilen, liegt in einem Platform-Feature (`Pascal`,
`Documents`, `Semantics` …) oder als Interface im Contract des anbietenden Features, das der Host verbindet.

Die Kanten von heute stehen als schrumpfende Liste unter `knownEdges` der Regel `architecture-feature-cycle` in
`atlas.json` (Stand des Umbaus: 354 Kanten, ein Zyklus). Eine neue Kante ist ein Befund, eine abgebaute wird gestrichen.

| Von | Nach | Erlaubt | Stand |
|---|---|---|---|
| `Lsp` | `Rules`, `Editing` | nein | heute die meisten Kanten: Der Server ruft Prüfregeln und Refactorings direkt |
| `Mcp` | `Lsp`, `Editing` | nein | MCP-Werkzeuge nutzen heute dieselben Dienste wie die LSP-Methoden |
| `Rules` | `Editing` | nein | Korrekturen nutzen heute Editing-Helfer (uses-Listen, Klassenvervollständigung, Code-Aktionen) |
| `Editing`, `Rules` | ein Hosted-Feature weiter oben | nein | schon heute ohne Kante: gemeinsame Wertetypen liegen tiefer (`TTextEdit` in `Documents.Contract`, `TDeclaredTypes` in `Pascal.DeclaredTypes`), Links ins Wiki im Index (`Index.DocWiki`), die Unit-Suche bei den Regeln (`Rules.Providers.UnitLookup`) |
| `Lsp`, `Rules`, `Editing`, `Mcp` | `Semantics` | ja | Namensauflösung und Datenfluss sind Platform |
| `Semantics` | `Lsp`, `Rules`, `Mcp` | nein | schon heute ohne Kante |
| `Semantics` | `Editing` | nein | heute noch drei Units (`Semantics.UsesUsage`, `Semantics.Reassigned`, `Semantics.ResolvedSignatures`) auf Editing-Bausteinen (uses-Listen, Routinenrumpf, lokale Namen, Signaturen); der Zyklus `Editing, Semantics` steht befristet unter `known`, bis die Bausteine nach `Pascal` ziehen |

### Keine Zyklen zwischen Features

Features desselben Ausgabeartefakts (`Atlas.Core.Lsp`, `Atlas.Core.Hover` …) bilden keinen Zyklus. Gezählt wird
jeder uses-Eintrag, interface und implementation, auch auf Contract-Units: Ein Contract, der einen anderen Contract
verwendet, bindet sein Feature ebenso an. Tests, Werkzeuge und Vorlagen zählen nicht.

- `Tools/Check-FeatureCycles.ps1` prüft das ganze Repository, die Regel `architecture-feature-cycle` meldet im Editor
  den uses-Eintrag, der einen Zyklus schließt oder gegen eine Richtung läuft. Beide lesen die Optionen der Regel aus
  `atlas.json` und prüfen die Fallliste `Tests/Data/Architecture/feature-cycles.json`.
- Richtungen stehen unter `directions`: `Präfix: A < B < C` (B und C dürfen A verwenden, nicht umgekehrt) und
  `Präfix: A | B` (keine Kante zwischen A und B).
- Bestehende Zyklen stehen unter `known`, Kanten gegen eine Richtung unter `knownEdges`. Beide Listen schrumpfen
  nur: Ein Eintrag, der nicht mehr genau stimmt, ist ein Fehler und wird gekürzt.
- Zyklus auflösen: die gemeinsamen Typen in das untere Feature verschieben (oft ein Contract), eine Unit in das
  Feature verschieben, zu dem sie gehört, oder die Abhängigkeit über einen Haken umdrehen, den die Komposition setzt.

## Verzeichnisstruktur

```text
Atlas.groupproj          Projektgruppe (Build-Reihenfolge: Text, WinBase, Common, Windows, Anwendung, IDE-Plugin, Tests)
Packages/
  Atlas.Text/
    Atlas.Text.dpk/.dproj
    Source/<Feature>/              Zeilen, Zeichen, Kodierung, URIs, Diff, Fuzzy (auch Editierabstand und Tippfehlersuche), JSONC, Entities, Version, Defines
  Atlas.WinBase/
    Atlas.WinBase.dpk/.dproj
    Source/<Feature>/              Windows-Code für Server und Plugin: Prozessstart mit Handle-Liste
  Atlas.Common/
    Atlas.Common.dpk/.dproj
    Source/<Feature>/              ein Ordner je Platform-Feature, darin optional Rollenordner
  Atlas.Windows/
    Atlas.Windows.dpk/.dproj
    Source/<Feature>/
  Atlas.Linux/
    Source/<Feature>/              Gegenstücke der Windows-Adapter für den Linux-Bau (FPC)
  Atlas.IDE.Base/
    Atlas.IDE.Base.dpk/.dproj
    Source/Core/  Source/UI/  Source/IDE/   (Schichten des Plugins, #406)
Application/
  AtlasServer.dpr/.dproj
  Source/
    Shell/                         heute alle Units des Hosts (Einstieg, Komposition, MCP-Werkzeuge, Linter, Arbeitsbereich);
                                   Ziel: Foundation/  Core/  Adapters/  Platform/  Features/  Shell/ (Host-Rollen)
Setup/                             Daten des Release-Pakets: Tipps, Vorlagen, Profile, Beispiele, tips.json (der Installer AtlasSetup ist seit 1.2.0 entfernt)
Tests/
  Atlas.Tests.dpr/.dproj
  Text/  Common/  Windows/  Application/  IDE.Expert/  (Tests je Ausgabeartefakt)
  Data/Protocol/                   aufgezeichnete Nachrichtenfolgen für Protokolltests (JSON)
Editors/ClaudeCode/                Plugin für Claude Code (LSP und MCP)
schemas/                           JSON-Schema von atlas.json, Quelle für Doku und Einstellungsdialog
Tools/                             Hilfsskripte; Tools/Linux: Linux-Bau des Servers mit FPC
Output/<Plattform>/<Konfiguration>/ Build-Ausgabe (nicht versioniert): Dcu, Dcp, Bpl, Bin
```

Die Anwendung und das Testprojekt binden die Packages statisch ein: Sie finden die DCUs der Packages in `Output/<Plattform>/<Konfiguration>/Dcu/<Package>`. Deshalb müssen die Packages vor der Anwendung gebaut werden; die Projektgruppe regelt das.

## Benennung

```text
Ausgabeartefakt.Feature.Rolle.Sache
```

- Präfixe der Ausgabeartefakte (Whitelist): `Atlas.Text`, `Atlas.WinBase`, `Atlas.Common`, `Atlas.Windows`, `Atlas.Linux`, `Atlas.IDE.Base`
- `Atlas.Text`-Units heißen `Atlas.Text.<Feature>` (Feature-Wurzel ohne Rolle, z. B. `Atlas.Text.Lines`); sie enthalten nur reine Funktionen und Records ohne Zustand, ohne `inline` und ohne Standardparameter, keine Contracts oder Provider
- Units der Anwendung tragen kein Präfix, z. B. `Shell.Application`
- Units im Wurzelverzeichnis eines Features tragen keinen Rollenbezeichner, z. B. `Atlas.Common.Product.Version`
- Ausnahme Plugin (#406): Die Units von `Atlas.IDE.Base` heißen nach ihrer Schicht `Atlas.Core.*` (Datenmodell, Matching, LSP-Client; ohne VCL und Open Tools API), `Atlas.UI.*` (Fenster; nur VCL) und `Atlas.IDE.*` (Open Tools API, Tastaturbindung, Einstellungen), darunter `Feature.Rolle.Sache`. `Core` und `UI` verwenden nie `Atlas.IDE.*`, `Core` nie `Atlas.UI.*`; geprüft durch `Tools/Check-PackageDependencies.ps1`. So lassen sich `Core` und `UI` später ohne Codeänderung in ein Runtime-Package auslagern.
- Rollenbezeichner sind reserviert: `Contract`, `Providers`, `Adapters`, `Internals`, `Hosting`, `Composition` (Features) sowie `Foundation`, `Core`, `Shell`, `Adapters`, `Platform` (Host)

## Importregeln

Platform-Features in den Packages importieren weder Host noch Hosted-Features:

| Importierende Rolle | Darf importieren |
|---|---|
| Contract | eigenes Contract, fremdes Contract |
| Internals | eigenes Contract und Internals, fremdes Contract und Root |
| Providers, Adapters, Root | eigenes Contract, Internals und Root, fremdes Contract und Root |
| Composition | eigenes Contract, Providers, Adapters, Root, Composition und Hosting, fremdes Contract und Root |
| Hosting | eigenes Contract und Hosting, fremdes Contract und Root |

Für die Anwendung gelten die Host-Matrix und die Hosted-Feature-Matrix. Hosted-Features importieren sich nie gegenseitig; feature-übergreifende Abläufe orchestriert der Host.

Host-Matrix (Host-Units ohne Präfix, je Host-Rolle):

| Importierende Host-Rolle | Darf im Host importieren | Darf von Platform-Features importieren |
|---|---|---|
| `Foundation.*` | Foundation | Contract |
| `Core.*` | Foundation, Core, Platform | Contract, Root |
| `Shell.*` | alle Host-Rollen | alles außer Internals, auch Sub-Contracts und die übrigen Teile einer Verschachtelung |
| `Adapters.*` | Foundation, Core, Adapters, Platform | Contract, Root, Sub-Contracts (nur zum Implementieren) |
| `Platform.*` | Platform | Contract, Root |

Ein Platform-Feature importiert nie eine Host-Unit und kein Hosted-Feature.

Hosted-Features der Anwendung heißen `Feature.Rolle.Sache` ohne Präfix und liegen unter `Application/Source/Features/<Feature>/`; ihr erstes Namenssegment steht in der Liste `hostedFeatures` (`atlas.json`, Regel `architecture-role-import`) und in `$HostedFeatures` von `Tools/Check-PackageDependencies.ps1`. Innerhalb des Features gilt die Matrix oben. Nach außen importiert ein Hosted-Feature nur `Foundation.*` sowie Contract und Root von Platform-Features (der Contract nur Contracts), nie Core, Platform, Adapters oder Shell des Hosts und nie ein anderes Hosted-Feature. Vom Host aus importiert es nur die Shell (alles außer Internals); Host-Adapters sehen nur seinen Contract und implementieren seine Sub-Contracts.

#### Verschachtelung

Ein Provider oder Adapter kann eigene Bedürfnisse haben (eigener Contract, Internals, Providers). Sie liegen bei ihm, nicht beim Feature: Ein zweiter Rollenbezeichner im Namen eröffnet eine Verschachtelung, das Fragment davor ist ihr Träger. Unter `Atlas.Common.Server.Providers.Authentication.` sind `Cache` der Träger (Root der Struktur mit den Eigenschaften von Providers), `Cache.Store` ein weiteres Root-Fragment, `Cache.Contract` der Sub-Contract und `Cache.Internals.*` die Internals der Struktur.

- **Innen** (beide Namen gleichen sich bis einschließlich des Trägers): Es gilt die Matrix relativ zum Träger, der die Stelle von Root einnimmt. `Cache` darf `Cache.Internals.*` und `Cache.Store` importieren, aber nicht `Cache.Adapters.*`.
- **Außen:** Die Struktur erbt die Importrechte des Trägers, der Sub-Contract nur die Contract-Rechte. Den Sub-Contract importieren Geschwister derselben äußeren Rolle (`ClientUser` unter `Providers`), die Composition des Features, die Shell und Host-Adapters; Feature-Root, Internals, Contract und fremde Features nicht. Die übrigen Teile der Struktur sehen nur Composition und Shell, ihre Internals niemand.
- Ein wiederholter Rollenbezeichner zählt als Sache (`Providers.P.Providers.X` ist `Providers.P.X`). Zwei Root-Fragmente einer Struktur (`Cache.Store`, `Cache.Index`) verraten ihren Träger nicht im Namen und gelten untereinander als Geschwister der äußeren Rolle.
- Zwei Rollenbezeichner hintereinander sind ebenfalls eine Verschachtelung: `Feature.Composition.Adapters` wäre der Adapters-Teil der Struktur `Feature.Composition`, den deren Root nicht importieren darf. Teile einer Composition heißen deshalb nach ihrer Sache ohne Rollenbezeichner (`Composition.HostAdapters`, `Composition.IdeAdapters`).

### Automatische Prüfung

Die Matrix wird zweimal umgesetzt und gegen dieselbe Fallliste `Tests/Data/Architecture/role-imports.json` getestet (je Matrixzelle ein Fall):

- `Tools/Check-PackageDependencies.ps1` (CI, ohne Delphi) prüft alle Units unter `Packages/` und `Application/`; `-SelfTest` prüft nur die Fallliste.
- Die Prüfregeln `architecture-role-import` und `architecture-contract-content` (`Atlas.Common.Rules.Builtin.Architecture`, `TArchitectureMatrix`) zeigen Verstöße im Editor und in der Selbstprüfung des Servers. Sie sind experimentell und ohne `prefixes` stumm.

Eingeordnet wird nach `Ausgabeartefakt.Feature.Rolle.Sache`: längstes passendes Präfix, dann Feature, dann der erste Rollenbezeichner an beliebiger Stelle danach oder Root (`Atlas.Common.Lsp.Hover.Contract` ist ein Contract von `Lsp`); jeder weitere Rollenbezeichner eröffnet eine [Verschachtelung](#verschachtelung). Units ohne Präfix mit einer Host-Rolle als erstem Segment gehören zum Host; alles andere (RTL, VCL, `Setup.*`, Tests) wird nicht geprüft. Contract-Units, auch Sub-Contracts, dürfen im interface keine Klassen deklarieren und kein Framework (VCL, FMX, Windows-API, Open Tools API) einbinden, außer genehmigten Ausnahmen. Gemeinsame Typen mehrerer Units eines Features, die kein Vertrag nach außen sind, heißen `…<Sache>.Types` (Root), nicht `…<Sache>.Contract`.

### Rollen Adapters und Providers (#1443)

Die Rollen folgen dem Konzept ohne Abweichung; maßgeblich ist, wessen Interface eine Klasse implementiert, nicht ob sie Platte, Prozess oder Netz berührt:

- **Providers** implementieren Interfaces aus dem **eigenen** Contract (`Atlas.Core.Completion.Providers.Snippets` erfüllt `IAtlasCompletionProvider` aus `Atlas.Core.Completion.Contract`).
- **Adapters** implementieren Interfaces aus dem Contract eines **fremden** Features. Fremd ist auch dasselbe Feature in einem anderen Ausgabeartefakt oder einer anderen Schicht: `Atlas.Windows.Compiler.Adapters.ProcessRunner` implementiert `ICompilerProcess` aus `Atlas.Common.Compiler.Contract`, eine Unit von `Atlas.IDE.Welcome` eine Quelle aus `Atlas.UI.Welcome`.
- Die Verträge zwischen Modulen (`Atlas.IDE.Contracts.*` in Base) sind für jedes Modul ein fremder Contract: Ein Modul erfüllt sie in `Atlas.IDE.<Modul>.Adapters.<Sache>`.
- Eine Unit ohne Rolle (Root), `Internals` und `Contract` implementiert kein Interface eines fremden Features; diese Klasse gehört in eine eigene Unit unter `Adapters`. Ausgenommen sind `Composition` und `Hosting` (Modulklassen, die `IAtlasModule` und die Quellen aus `Atlas.Core.Modules.Contract` erfüllen, Notifier und Wizards der Open Tools API) und die Host-Units der Anwendung (`Shell.*`).
- Ein Interface, das ein anderes Feature implementiert, steht im Contract seines Features (Rolle `Contract` oder `Atlas.IDE.Contracts.*`), auch wenn nur die Shell es implementiert.
- Eine Unit unter `Adapters` bzw. `Providers` implementiert mindestens ein solches Interface, auch geerbt über einen Vorfahren des eigenen Features. Was den Rand nach außen ohne Vertrag kapselt, ist Root oder `Internals`.
- Adapters und Providers erzeugt nur die eigene Composition oder der Host (Rollenmatrix); wer sie braucht, bekommt sie über ihr Interface.

`Tools/Check-PackageDependencies.ps1` prüft diese Regeln für alle Units unter `Packages/` und `Application/`; `Tools/Test-PackageDependencies.ps1` deckt jede Regel mit einem absichtlichen Verstoß ab. Noch nicht umgebaute Altfälle stehen in `Tools/AdapterRoles.known.txt` (je Zeile Regel, Unit, Klasse, Interface). Ein neuer Verstoß ist ein Fehler, ebenso eine Zeile, die nicht mehr vorkommt; die Liste wird nur kürzer (`-UpdateAdapterRoles` schreibt sie nach einem Umbau neu).

### Selbstprüfung je Plugin-Package (#2011)

Jedes Plugin-Package (`Packages/Atlas.IDE.*`) hat eine eigene `atlas.json` und `atlas-baseline.json`. Atlas nimmt bei `AtlasServer --check Packages/<Package>/<Package>.dproj` und im Editor die nächstgelegene `atlas.json` über dem Projekt und die Baseline daneben; ohne eigene Datei gälte für ein Modul die Wurzel-Konfiguration mit abgeschalteten Metriken.

- Quelle der Konfiguration ist `Packages/atlas.plugin.json` (Profil `strict`, Ausnahmen des Plugins). `Tools/Update-PackageConfigs.ps1` schreibt daraus die gleiche `atlas.json` in jedes Plugin-Package und übernimmt die Architektur- und Verbotsregeln aus der `atlas.json` im Stamm; `-Check` läuft in CI. Die `atlas.json` der Packages nicht von Hand ändern.
- Ein neues Modul-Package bekommt seine `atlas.json` durch `pwsh Tools/Update-PackageConfigs.ps1`.
- `Tools/Linux/Check-PluginPackages.sh` prüft jedes Package mit seiner Konfiguration und Baseline; jeder Treffer außerhalb der Baseline, auch ein Hinweis, lässt den Lauf (und den Job in `linux-server.yml`) scheitern. Neue Treffer werden behoben, nicht in die Baseline aufgenommen.
- `Tools/Check-Baselines.ps1` (CI) meldet Baseline-Einträge auf fehlende Dateien und jede Regel, deren Einträge gegenüber dem Zielbranch zunehmen, dazu in `atlas-duplicates.json` jede neue oder gewachsene Gruppe (Ausnahme nur mit `Neue Kopien: …` im Pull Request, siehe `docs/Zusammenfuehren.md`); neue Einträge zu `metric-class-size` nur mit einer Zeile `Größere Klasse: <Name> – <Grund>` je Klasse. Nur wenn sich die `atlas.json` eines Packages ändert, wird seine Baseline neu erzeugt (`AtlasServer --check Packages/<Package>/<Package>.dproj --update-baseline`).
- Beim Verschieben einer Unit in ein anderes Package wandern ihre Einträge nicht mit: Baseline beider Packages neu erzeugen und prüfen, dass keine Regel wächst.
- Außerhalb der Plugin-Packages (Atlas.Common, Atlas.Windows, Application, Tests) gilt die `atlas.json` im Wurzelordner. Von den Metrikregeln sind dort nur `metric-method-length` und `metric-cyclomatic-complexity` an, mit `atlas-baseline.json` im Wurzelordner als Bestand. Der Schritt „Metrikregeln außerhalb der Plugin-Packages“ in `linux-server.yml` (`AtlasServer --check . --no-index --profile metriken --rules metric-method-length,metric-cyclomatic-complexity --format json`, ausgewertet wie in `Check-PluginPackages.sh`) bricht bei jeder neuen Routine über den Grenzwerten ab, auch als Hinweis (das Profil `metriken` aus derselben `atlas.json` lässt die teuren semantischen Regeln weg, `--rules` allein filtert nur die Ausgabe); `Tools/Check-Baselines.ps1` zählt die Baseline mit. Wer eine Routine aus der Baseline zerlegt, schreibt sie mit `AtlasServer --check . --no-index --profile metriken --rules metric-method-length,metric-cyclomatic-complexity --update-baseline` neu.
- Weil `duplicate-routine-body` auch in den Packages läuft, steht eine Kopie, die in `atlas-duplicates.json` aufgenommen wird, auch in der Baseline ihres Packages; nach dem Zusammenlegen fallen die Einträge beim nächsten Neuschreiben heraus.

### Keine Unit-Zyklen (#1450)

Auch über implementation-uses bilden die Units unter `Packages/` und `Application/` keinen Zyklus: `AtlasServer --check . --units 'Packages/**,Application/**' --rules uses-cycle` meldet nichts. Eine Unit eines Zyklus ließe sich weder allein testen noch austauschen. Die Muster dafür:

- Gemeinsame Typen eines Features stehen in seiner Contract-Unit. `Atlas.Common.Editing.Contract` trägt die Typen der Schnellbefehle (`TSlashContext`, `TSlashCommand`, `ISlashHost`, `TSlashSettings` …) und den Kontext der uses-Aktionen (`TUsesContext`). Die Befehls-Units (`*Commands`) binden nur den Contract ein und melden ihre Befehle über `TSlashRegister`; nur das Register `Atlas.Common.Editing.SlashCommands` bindet alle Befehls-Units ein. Es bleibt eine Root-Unit, weil Lsp, Rules und `ClassActions` es nutzen (eine Composition dürften sie nach der Matrix nicht einbinden).
- Was zwei Units gemeinsam brauchen, kommt in eine tiefere Unit: `TLspSymbolKind` in `Atlas.Common.Lsp.Contract`, die Formularprüfung in `Atlas.Common.Lsp.FormMentions`, JSON-Strings schreiben und JSON nachsichtig lesen in `Atlas.Text.Json`, Dateiadressen des Plugins in `Atlas.Core.Lsp.Uris`, die Steuerelemente `Atlas.UI.Settings.ChoiceBox` und `Atlas.UI.Tracker.DocBox`.
- Eine Funktion gehört zu ihren Daten: Die Nutzung je Befehl fragt `TAtlasIdeCommandUsage.UsageOf`, nicht die Tastenkürzel-Tipps; der Rückruf „Testen“ des Abfragedialogs (`TAtlasQueryTestEvent`) steht beim Dialog, nicht auf der Seite, die ihn öffnet.

### Genehmigte Ausnahmen

Die Liste steht einmal in `atlas.json` (`allow` der beiden Regeln) und gilt für Skript und Linter. JSON kennt keine Kommentare, darum die Begründungen hier. Platzhalter nennen immer die Rolle des Ziels (`Atlas.Core.*.Providers.*`), und keine Ausnahme gibt Internals frei, auch nicht die einer Struktur: Beide Prüfungen melden einen solchen Import trotz passendem Eintrag.

**Framework-bezogene Importe eines Contract** (Konzept 7.1):

| Ausnahme | Grund |
|---|---|
| `Atlas.Common.Rules.Contract -> Atlas.Common.Pascal.SyntaxTree` | Der Syntaxbaum ist das Framework, auf dem jede Prüfregel läuft (wie die RTL für andere Verträge), und hängt selbst nur an Contracts; ein Baum-Interface würde alle Regeln ändern. |
| `Atlas.Common.Semantics.Contract -> Atlas.Common.Pascal.SyntaxTree` | `ITreeUnits` (#1322) gehört zu genau einem Syntaxbaum und muss ihn wiedererkennen; aus demselben Grund wie bei `Rules.Contract`. |
| `Atlas.Common.Documents.Contract -> Atlas.Text.Lines` | `TTextPosition` ist derselbe Typ wie in `Atlas.Text`; `Atlas.Text` hat nur zustandslose Funktionen und Records. |
| `Atlas.Core.Lsp.Contract -> Atlas.Text.Json`, `Atlas.Core.Lsp.ProjectContext.Contract -> Atlas.Text.Json` | Die Verträge reichen JSON-Werte des Protokolls weiter; `Atlas.Text.Json` ist die gemeinsame JSON-Schicht aus zustandslosen Lese- und Schreibhelfern. |
| VCL in Verträgen der UI-Schicht (`Atlas.UI.*` → `Vcl.*`, im Skript `$ContractFrameworkAllow`) | Verträge der Schicht `Atlas.UI` reichen Steuerelemente, die Base und Module mit derselben VCL bauen (`Atlas.UI.Settings.Contract`: die Bausteine einer Optionsseite). Eigene Interfaces je Steuerelement wären nur Hüllen. Der Code kommentiert die Ausnahme am uses. |
| `Atlas.Common.Dfm.Contract.TDfm*` (Contract-Inhalt) | `TDfmObject` und `TDfmDocument` sind reine Datenklassen eines Baums (Besitz der Kinder, kein Verhalten); Verschieben änderte rund 20 Units ohne Abhängigkeitsgewinn. |

**Composition in der Rolle eines Hosts:** Das Plugin hat keine eigene Namensgruppe für den Host. Seine Kompositionswurzel (`Atlas.IDE.CodeInsight.Composition.*` in Base) und die Composition jedes Moduls übernehmen dessen Aufgabe und erzeugen die Providers und Adapters fremder Features, die nach der Matrix nur ein Host erzeugen dürfte. Erlaubt ist genau das, nie Internals:

| Ausnahme | Grund |
|---|---|
| `Atlas.IDE.CodeInsight.Composition.HostAdapters -> Atlas.Core.*.Providers.*` | Der Teil der Kompositionswurzel, der die Providers der Core-Features erzeugt (Serverprozess, Ordnerbeobachter, Quellen von Vervollständigung und Parameter-Hint, Ziel und Sicherung des Änderungsprotokolls, Update-Quelle) und über Schnittstellen und Fabriken an die übrigen Teile der Wurzel und an die Features weiterreicht. |
| `Atlas.IDE.CodeInsight.Composition.HostAdapters -> Atlas.IDE.Undo.Adapters.*` | Dieselbe Unit setzt das Ziel des Änderungsprotokolls auf der Platte (`Atlas.IDE.Undo.Adapters.Target`) neben dessen Sicherung ein. |
| `Atlas.IDE.CodeInsight.Composition.IdeAdapters -> Atlas.IDE.*.Adapters.*`, `Atlas.IDE.CodeInsight.Composition.ProblemsAdapters -> Atlas.IDE.Problems.Adapters.*`, `Atlas.IDE.CodeInsight.Composition.UiAdapters -> Atlas.UI.*.Adapters.*` | Die übrigen Teile der Wurzel erzeugen die Adapter der IDE- und UI-Features von Base: `IdeAdapters` Einstellungsspeicher in der Registry, aktiven Editor und offene Puffer, Sicht des Planers, Puffer der Editoransicht, Palette als Befehlsziel, Einrichtung, Schattentext aus dem Index und Statuszeilen des Atlas-Felds; `ProblemsAdapters` Server und IDE für den Ablauf der Probleme; `UiAdapters` die Fenster von Vervollständigung, Parameter-Hint und Tooltip als Ansichten der Controller. Diese Features haben keine eigene Composition. |
| `Atlas.IDE.Assistants.Composition.HostAdapters`, `Atlas.IDE.BuildTools.Composition`, `Atlas.IDE.Debug.Composition`, `Atlas.IDE.Tests.Composition`, `Atlas.IDE.Tracker.Composition`, `Atlas.IDE.VersionControl.Composition` jeweils `-> Atlas.Core.*.Providers.*` | Die Composition eines Moduls erzeugt die Providers der Core-Features, die das Modul mitbringt (KI-Anbieter und Anmeldedaten, Aufgabenprozesse, Vervollständigung von Ausdrücken, Prozessläufer der Versionsverwaltung, Tracker- und CI-Anbieter). |
| `Atlas.IDE.VersionControl.Composition -> Atlas.Core.VersionControl.Composition` | Das Modul ruft die Composition des Core-Features als Vorgabe auf (Konzept 7.6). |

## Kommentare

Unit-Köpfe und Kommentare beschreiben den heutigen Entwurf und seinen Grund, nicht seine Geschichte. Ein Grund lässt sich fast immer ohne „früher“ sagen: „sonst …“, „damit …“, „statt …“. Wann und warum etwas umgebaut wurde, steht im Issue und in der Git-Historie; die Issue-Nummer im Kommentar genügt als Verweis. Umzüge zwischen Units oder Packages („seit #… im Modul“, „bis #… in …“) gehören nicht in den Kommentar.

Verweise zeigen nur auf Quellen, die im Repository liegen oder öffentlich sind (Issues, Dateien, Dokumentation). Steht eine Entscheidung woanders, gehört ihr Grund in einem Halbsatz an die Stelle. Das gilt auch für Mockups, Entwurfsrunden und Varianten aus Gesprächen und für datierte Quellen wie „Diagnoselog vom …“ oder „Rückmeldung vom …“: An ihre Stelle tritt die Messung oder der Grund selbst („gemessen 3 GB bei acht Projekten“, „sonst …“).

## Tests

- Unit-Tests mit DUnitX je Unit in `Tests/<Ausgabeartefakt>/<Feature>/`.
- Testunits ohne Windows- und VCL-Bezug laufen zusätzlich unter FPC (`Tools/Linux/Test-Fpc.sh`, Liste `Tools/Linux/FpcTests.txt`) in jedem Pull Request; neue gehören in die Liste, sobald sie dort grün sind.
- Protokolltests: `Tests/Data/Protocol/*.json` enthalten Schritte `send` und `expect`; `Atlas.Common.Lsp.ProtocolReplay` spielt sie gegen den Server ohne Threads ab und vergleicht die Antworten feldweise. Neue Aufzeichnung = neue JSON-Datei, kein Code nötig.
- Fuzzing: zufällig beschädigter Code (fester Startwert) darf den Parser weder abstürzen noch hängen lassen.
- Korpustest: parst RTL und VCL aus `$(BDS)\source` oder dem Ordner in `ATLAS_CORPUS`; ohne beides wird er übersprungen.
- Leistungsmessung mit festen Zielwerten (Syntaxfehler < 200 ms, Gliederung und Faltbereiche < 100 ms).
- Der Parser begrenzt die Verschachtelung auf 256 Ebenen und gibt Bäume iterativ frei, damit kaputter Code keinen Stapelüberlauf auslöst.
- Leckmessung je Test: Produktivcode wird nicht für die Messung geformt. Gemeinsame Sperren, die bis zum Programmende leben, entstehen über `TAtlasSharedLock.New` (`Atlas.Text.Locked`, Monitor-Datensatz gleich beim Anlegen); langlebige Tabellen bekommen beim Anlegen eine Anfangsgröße für den üblichen Betrieb, statt bei null Einträgen geleert zu werden. Einmal-Belegungen, die nur die Messung stören (Singletons der RTL, gemeinsame Kataloge), stehen benannt in `Tests/Support/Atlas.Tests.FirstUse.pas`; `Tools/Check-TestWarmUps.ps1` lehnt `[SetupFixture]`-Aufwärmer und von Hand vorgewärmte Sperren (`TMonitor.Enter` direkt gefolgt von `TMonitor.Exit`) ab.

## DI-Strategie

Komposition von Hand (keine Container-Bibliothek). Composition-Units tragen deshalb kein Strategie-Suffix. Wird später eine zweite Strategie (z. B. Spring4D) eingeführt, erhalten die Units ein Suffix nach der Strategie.

## Umgesetzte Features

Die Tabellen der umgesetzten Features (Feature, Units, Inhalt) stehen je Bereich in eigenen Dateien. Neue Features tragen ihre Zeile in die Datei ihres Bereichs ein.

- [Server: Plattform, Protokolle und Host](architektur/Server-Plattform.md): Plattform-Features von `Atlas.Common` (Protokoll, Dokumente, Parser, Projekte, Index, Konfiguration), die Windows- und Linux-Adapter und der Host `Shell`.
- [Server: Fachlogik](architektur/Server-Fachlogik.md): Fachlogik des Servers: Namensauflösung, Metriken, Prüfregeln, Architektur, Hotspots, Profile, Abfragen.
- [Plugin: Editor, Vervollständigung und Fenster](architektur/Plugin-Editor.md): LSP-Client, Vervollständigung, Hilfen im Editor, Gliederung, Analyse-Fenster und Ergebnisfenster des Plugins.
- [Debuggen und Profiling](architektur/Debuggen.md): Server- und Plugin-Teile der Debug-Funktionen.
- [Plugin: Befehle, Suche, Bauen, Diagnose](architektur/Plugin-Werkzeuge.md): Befehle, Suche, Erzeugen, Formulare, Tooltip, Bauen und Tests, Diagnose, Grundbausteine des Editors und Einstellungen je Projekt.
- [Umbauen und Schreiben](architektur/Umbauen.md): Umformungen, Schnellkorrekturen und Hilfen beim Schreiben, Server-Teil und Plugin-Teil.
- [Plugin: Dienste, Module und Oberfläche](architektur/Plugin-Dienste.md): Benachrichtigungen, Einstellungen, Updates, Willkommensseite, Versionsverwaltung, Build-Server, Issue-Tracker, Diagnose, Einrichtung und die Grundbausteine der Atlas-Fenster.

## Ablauf einer Anfrage

Im Server:

```text
stdin ─► Lese-Thread ─► Posteingang ─► TJsonRpcConnection.Run ─► TJsonRpcDispatcher ─► Handler
           │ $/cancelRequest sofort                                  │ Guard: TLspLifecycle
           ▼                                                         ├─ normal: im Run-Thread
     TJsonRpcPendingRequests ◄── Abbruchsignal ────────────────────── └─ nebenläufig: Thread-Pool
stdout ◄─ TJsonRpcStreamTransport (threadsicher) ◄──────── Antwort ◄───────┘
```

Threads und Reihenfolge:

- Benachrichtigungen und normale Anfragen (`RegisterRequest`) laufen nacheinander im Thread von `Run`. So kommen z. B. `didChange`-Nachrichten in der gesendeten Reihenfolge an, und solche Handler brauchen keine Sperren.
- Nebenläufige Anfragen (`RegisterConcurrentRequest`) laufen im Thread-Pool und erhalten ein `IJsonRpcCancellationToken`. Sie dürfen nur threadsicheren Zustand lesen, etwa eine Momentaufnahme des Dokuments, und sollen das Token regelmäßig prüfen. Ein Abbruch wird zur Fehlerantwort `RequestCancelled` (-32800).
- `$/cancelRequest` führt der Lese-Thread sofort aus, also auch, während `Run` beschäftigt ist. Eine normale Anfrage, die vor ihrer Verarbeitung abgebrochen wurde, wird ebenfalls mit `RequestCancelled` beantwortet.
- Jede Anfrage hat ein Zeitlimit (`RequestTimeoutMs` in `Shell.Composition`, 10 s). Läuft es ab, bricht `TJsonRpcWatchdog` die Anfrage über ihr Abbruchsignal ab und protokolliert eine Warnung. Der Parser fragt das Signal über `IPascalCancellation` ab.
- Jede Anfrage sieht der optionale `IJsonRpcRequestObserver` des Dispatchers vor und nach dem Handler im selben Thread, mit Ergebnis, Wartezeit und Laufzeit; darüber schreibt `Shell.Diagnostics` das anonymisierte Diagnoselog (#647). Features melden Grundcodes leerer Ergebnisse über `TRequestDiagnostics`.
- Unerwartete Ausnahmen eines Handlers (nicht `EJsonRpcError`) meldet der Dispatcher über `OnRequestFailed`; die Komposition protokolliert Methode, gekürzte Parameter und Stacktrace. Bei einem Absturz nennt das Log die zuletzt verarbeitete Nachricht.
- Endet die Verbindung (`exit`, Eingabe geschlossen), bricht `Run` offene Anfragen ab und wartet höchstens `WorkTimeout` auf laufende.

Features, die Dateien auswerten, lesen Momentaufnahmen aus `IDocumentStore` (`TServerComposition.Documents`) und abonnieren dessen Ereignisse, um nur die geänderte Datei neu zu verarbeiten. Eine Momentaufnahme ändert sich nie und darf auch in nebenläufigen Anfragen gelesen werden. Befehle über `workspace/executeCommand` laufen der Reihe nach in der Nachrichtenschleife, solange sie mit `TLspCommands.Register` angemeldet sind; ein langer Befehl hält dann alle folgenden Anfragen auf. Lesende, threadsichere Befehle meldet die Komposition deshalb mit `RegisterConcurrent` an (Diagnose 06.11.2026); in Reihe bleiben Befehle, die Dateien schreiben, Einstellungen neu laden oder einen Bau anstoßen.

Neue LSP-Methoden registrieren ihre Handler in `Shell.Composition` am Dispatcher und tragen ihre Capability in `BuildCapabilities` ein.

## Schichten

Innerhalb von `Atlas.Common` hängen die Features in dieser Richtung voneinander ab (nur nach unten):

```text
Lsp            LSP-Methoden, Capabilities, Positionen
Architecture   Uses-Graph, Architekturübersicht (nutzt Index und die uses-Leser aus Editing)
Semantics      Namensauflösung, Kontrollfluss
Index          Symbolindex, Cache, Aufbau
Pascal         Lexer, Präprozessor, Parser, Syntaxbaum
Projects, Configuration, Documents, JsonRpc, Logging
RTL
```

`Lsp` verbindet Protokoll und Fachlogik; die Fachlogik darunter kennt kein JSON-RPC. `Shell` in der Anwendung setzt alles zusammen und ist die einzige Stelle, die Windows-Adapter und Common-Features verbindet.

Das IDE-Plugin (#406) hat drei Schichten, ebenfalls nur nach unten abhängig:

```text
Atlas.IDE.*    Open Tools API, Editor, Menüs, Einstellungsspeicher, Komposition
Atlas.UI.*     Fenster und Steuerelemente (nur VCL)
Atlas.Core.*   Datenmodell, Matching, LSP-Client, Einstellungen (ohne VCL und Open Tools API)
RTL
```

Das Plugin nutzt `Atlas.Common` nicht; es spricht mit dem Server nur über LSP.

### Struktur der IDE-Schicht

- **Grundbausteine `Atlas.IDE.Foundation.*`** (`Source/IDE/Foundation/`): Einstellungen, Editorpuffer und -stand, Editorstil, Tastenhaken und Tastenbelegung, Atlas-Symbol, Ergebnisfenster, Rinne, gezeichnete Elemente (#628), Strukturhervorhebung, Dateien und Projekte der IDE, Navigation. Sie verwenden aus der IDE-Schicht nur andere Grundbausteine und sind die Basis aller IDE-Features; ein Feature verwendet sie wie einen Contract.
- **Keine Zyklen zwischen Features:** Die Features von `Atlas.Core` und `Atlas.IDE` hängen nur in einer Richtung voneinander ab, gezählt über alle uses, auch auf Contracts (Abschnitt „Keine Zyklen zwischen Features“). Wo ein Feature ein anderes aufrufen muss, das schon von ihm abhängt, setzt die Kompositionswurzel einen Haken (z. B. `TAtlasEditorTestUnitLens.OnSwitchTestUnit`, `TAtlasOptionsHooks`) oder reicht eine Schnittstelle (`IAtlasCommandRegistry`) durch.
- **Kompositionswurzel `Atlas.IDE.CodeInsight.Composition`:** Die Wurzel selbst hält nur `Register` und `Unregister` und legt die Reihenfolge fest; die Teile liegen in `Atlas.IDE.CodeInsight.Composition.<Teil>` (Adapters, Session, Status, Build, Tools, Background, Drawing, Palette …, Features, Settings, Services, Leftovers), die einander ohne Zyklus verwenden. Nur `.Adapters` erzeugt Providers, Adapters und Compositions der Core-Features (genehmigte Ausnahme oben). Die Teile des Plugins stehen in `.Features` in Startreihenfolge in einer `TAtlasFeatureTable` (`Atlas.Core.Diagnostics.FeatureTable`): je Teil die Stufe des abgesicherten Starts bzw. die Einstellung, unter der es läuft, Start und Stop. `RegisterFeatures` startet beim Laden und nach jeder Einstellungsänderung, was gewünscht ist und noch fehlt; `Unregister` baut rückwärts ab.
- **Workspace-Edits:** `Atlas.Core.Editor.WorkspacePlan` (ohne Open Tools API, getestet) plant aus einem LSP-Workspace-Edit die Schritte je Datei (Puffer, Formular, Platte, Anlegen, Umbenennen, Löschen); `Atlas.IDE.Editor.WorkspaceEdit` führt den Plan in der IDE aus und protokolliert ihn als einen Satz im Änderungsprotokoll.
- `Tools/Check-PackageDependencies.ps1` prüft die Grundbausteine ohne andere `Atlas.IDE.*`-Units, `Tools/Check-FeatureCycles.ps1` die Feature-Zyklen.

### Module und Verträge des Plugins (ab 2.0)

Ab #1455 besteht das Plugin aus `Atlas.IDE.Base` (mit den Verträgen zwischen Modulen) und Modul-Packages (Debugger, Tracker, Welcome …). Diese Regeln gelten für jeden Code, der dafür entsteht. Begründung: Delphi lädt Known Packages in nicht garantierter Reihenfolge, ruft beim Entladen `Finalize` eines Packages auch dann, wenn ein anderes es noch importiert, und prüft die Binärschnittstelle zwischen Packages zur Laufzeit nicht (Fortschreibung „Laden, Entladen, Versionen“).

1. **Registrieren ohne Reihenfolge.** Registry und Verträge von Base bestehen ab der Unit-Initialisierung (verzögert erzeugte Singletons), nicht erst nach dem `Register` von Base. Das `Register` eines Moduls meldet nur einen Deskriptor an (ID, Name, Mindeststufe für den abgesicherten Start #722, `Start`, `Stop`, `IsActive`) und startet nichts; gestartet und gestoppt wird nur über die Feature-Tabelle von Base.
2. **Spät ankommende und verschwindende Module.** Base startet ein Modul auch, wenn es sich nach dem Start von Base anmeldet, und stoppt es beim Abmelden. Wer Beiträge anderer Module zeigt (Willkommensseite, Hover, Statusfeld, Palette), hört auf die Änderungsmeldung der Registry, statt einmal beim Start zu fragen.
3. **Abmelden ist synchron und vollständig.** Danach erreicht kein Aufruf mehr das Modul: keine Serverantwort, kein `TAtlasMainThread`-Eintrag (die Registry verwirft sie über `TAtlasMainThread.CloseModule`; Einträge mit Code in Base, die Modulobjekte einfangen, muss das Modul selbst vor dem Abmelden stillen), kein Timer, kein Ereignis (Vorbild `IAtlasCompletionProvider`).
4. **Jede Anmeldung hat einen Besitzer.** Feature-Slot, Einstellungsteil, Seite, Befehl, Menüeintrag, Statusfeldzeile, Editorleiste, Dock-Fenster, Tipp, Kachel, Hover-Beitrag: alles läuft über den `IAtlasModuleScope` des Moduls und trägt dessen ID; beim Abmelden löst Base alles in umgekehrter Reihenfolge.
5. **Base stoppt zuerst die Module.** Die Finalisierung von Base ruft `StopAll` vor dem Abbau eigener Registries und setzt danach „Base abgebaut“; Module melden sich in ihrer Finalisierung nur ab, solange Base noch läuft.
6. **Vertragsinhalte.** Über Package-Grenzen gehen Interfaces mit GUID, Records, `TArray<T>` und Methodenreferenzen; keine Typprüfung gegen generische Klassen (`is TList<…>`), keine `ClassName`-Vergleiche. Alle Verträge liegen in Base: allgemeine (Modul, Registry, Scope, Einstellungen) bei ihrem Feature, Verträge zwischen Modulen unter `Source/Contracts` (`Atlas.IDE.Contracts.*`, nur Interfaces und Records, kein Code). Ein eigenes Package `Atlas.IDE.Contracts` gibt es seit 04.11.2026 nicht mehr. Verträge heißen nach der Fähigkeit (`IAtlasIssueSource`), nicht nach Anbieter oder Verbraucher.
7. **Versions-Handschlag.** Base führt eine Vertragsversion als Konstante und als exportierte Funktion `AtlasCoreContractVersion`; ein Modul prüft sie zuerst in `Register` über `GetProcAddress` und meldet sich bei Abweichung nicht an, sondern zeigt einen Hinweis. Base und Module kommen immer aus demselben Bau; die Version steigt deshalb höchstens einmal je Release (auf den Wert des letzten Release-Tags + 1, sobald sich danach ein Vertrag ändert). Weitere Pull Requests im selben Release-Zyklus lassen sie stehen, sonst änderten parallele Pull Requests dieselbe Zeile verschieden; `Tools/Check-ContractVersion.ps1` prüft das.
8. **Modul-Identität.** „Gehört das zu Atlas?“ beantwortet die Modul-Registry von Base (HMODULEs der angemeldeten Module), nie `HInstance` oder `GetModuleName(HInstance)` eines einzelnen Moduls. Ressourcen von Base über `FindClassHInstance` einer Base-Klasse, den Installationsordner über eine Funktion von Base. Ein Hook, der nur das eigene Modul betrifft (`SetWindowsHookEx` mit `HInstance`), bleibt.
9. **Modulliste aus Anmeldungen.** Base enthält keine eingebauten Modulnamen. Ein Modul ist, was sich anmeldet, Atlas-Modul oder fremdes Modul. Base merkt sich jedes Modul, das sich einmal angemeldet hat (ID, Name, Version), und zeigt fehlende als „nicht installiert“; ihre Einstellungswerte bleiben erhalten.

Dazu gelten: Kein Modul requiret ein anderes, Base verweist auf kein Modul, Module requiren nur Base; Einstellungen bleiben zentral in Base, jedes Modul meldet seinen Teil (Schlüssel mit Vorgaben, Schema-Teil, Seite, Umbenennungen) an; Texte liegen je Modul in dessen Package. `Tools/Check-PackageDependencies.ps1` prüft die Package-Grenzen sowie Regel 6 und 8, soweit statisch erkennbar (mit #1455).

#### Muster eines Moduls (#1455)

Jedes Modul hat genau eine Kompositions-Unit `Atlas.IDE.<Modul>.Composition` (Vorlagen: `Atlas.IDE.Analysis.Composition`, `Atlas.IDE.Rules.Composition`):

- Die Klasse implementiert `IAtlasModule` und die Beitragsverträge, die das Modul anbietet. `Info` liefert über `TAtlasModuleHost.Info` (`Atlas.Core.Diagnostics.ModuleHost`) die Id (`atlas.<name>`), den Modulschalter (#1454), die Mindeststufe des abgesicherten Starts, die Version und das `HInstance` des Moduls.
- `RegisterModule` läuft in der Initialisierung. Es prüft zuerst mit `TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry)` den Handschlag (Regel 7; die erwartete Version kommt aus dem Modul), meldet dann an und stellt alles über `GScope.Provide` bereit. `UnregisterModule` läuft in der Finalisierung und ruft nur `TAtlasModuleHost.Unregister(GScope, cModuleId, ReleaseModule)`: Scope vergessen, solange Base läuft (Regel 5) bei der Registry abmelden, dann die Schritte des Moduls in `ReleaseModule` (oder `nil`). Die Reihenfolge des Abbaus steht damit nur in Base.
- Teile der Feature-Tabelle: `TAtlasFeaturePart.AtLevel` bzw. `.When` (`Atlas.Core.Modules.FeatureParts`) mit Start und Stop. Was ein Teil bei Base setzt (Haken, Statusfeld), nimmt sein Stop zurück.
- Beiträge, die Base einsammelt (`TAtlasModuleContributions`, nur von laufenden Modulen):

| Vertrag | Fähigkeit |
|---|---|
| `IAtlasCommandSource` | Befehle der Palette |
| `IAtlasMenuSource` | Atlas-Menü, Untermenü „Atlas“ im Editor, Ansicht › Atlas |
| `IAtlasKeySource` | Tasten |
| `IAtlasAppliesSettings`, `IAtlasFollowsTheme` | Einstellungen übernommen, Thema gewechselt |
| `IAtlasHoverValueSource` | Werte im Tooltip |
| `IAtlasTakenActions` | übernommene IDE-Aktionen |
| `IAtlasGutterLayer`, `IAtlasOverviewBookmarks` | Rinne und Übersichtsleiste |
| `IAtlasBuildVerdictListener`, `IAtlasTestRunner` | bewertete Builds, Tests ausführen |
| `IAtlasBulkFixer` | Sammelkorrektur in „Atlas-Prüfung“ |
| `IAtlasSettingsSection` | Abschnitt im Optionsdialog (`Atlas.UI.Settings.Contract`) |

- Einstellungen im Optionsdialog: `IAtlasSettingsSection` (`Atlas.UI.Settings.Contract`) über `GScope.Provide`. `AreaId` ist der Bereich (`x-area`); ohne Reiter dieses Bereichs legt die Seite einen an. In `Build` nimmt der Abschnitt die Bausteine von `IAtlasSettingsSectionHost`: Überschrift, Hinweis, Schalter, Zahl, Text und Auswahl an einem Schlüssel (`x-key`, Base lädt und speichert sie) und eigene Zeilen (`AddRow` mit den Schlüsseln, die der Abschnitt darin selbst über `IAtlasSettingsValues` in `Load`/`Save` liest und schreibt). Die Seite bindet Punkt, Zurücksetzen, Unterpunkt und Sperre an ihre eigenen Zeilen, nie an Elemente des Moduls; diese gibt das Modul in `Close` frei. Geht das Modul, schließt die Seite den Abschnitt; die Werte bleiben in der Ablage. Über die Package-Grenze gehen dabei VCL-Klassen (gemeinsame VCL), nie Klassen aus Atlas-Packages.
- Base baut nur die eigenen Einstellungen. Alles, was einem Modul gehört (Modulschalter und die Einstellungen darunter), baut das Modul als Abschnitt `Atlas.UI.<Modul>.SettingsSection`, abgeleitet von `TAtlasSettingsSection` (`Atlas.UI.Settings.Section`): `BuildRows` mit `ModuleSwitch`, `Switch`, `Number`, `Line`, `Key`, `Choice` und den eigenen Zeilen `Own…`; die Composition meldet ihn mit `TAtlas<Modul>…Section.ProvideIn(GScope)` an (je Optionsseite ein neuer Abschnitt). `AreaId` ist die Seite (`x-page`, z. B. „Compiler“) oder der Bereich (`x-area`); die Seite hat Vorrang. Wege zu Einstellungen eines anderen Moduls zeigt ein Abschnitt erst in `WindowReady` und nur, wenn `IAtlasSettingsSectionHost.Shows` die Zeile findet.
- Knoten je Package (#1903): Unter Tools › Optionen › Atlas stehen die Übersicht „Atlas“ (Hauptschalter, Stand der Packages, Suche), „Module“ mit „Base“ und je angemeldetem Modul ein Knoten (`Atlas.IDE.Settings.ModuleNodes`, alphabetisch, An- und Abmelden zur Laufzeit), dann Snippets, Tastenkonflikte, Server. Jeder Knoten zeigt dieselbe Optionsseite, gefiltert auf seinen Besitzer (`TAtlasSettingsNodeScope`): Zeilen aus Abschnitten gehören dem Knoten ihres Abschnitts, übrige Einstellungen dem Modul ihres Modulschalters (`x-module` über die Hauptschalter), alles andere Base. Gespeichert werden nur die Änderungen eines Knotens (`TAtlasSettingsMerge`), damit zwei Knoten sich nicht überschreiben.
- Regel X, Einstellungen über Modulgrenzen: Der Eigentümer einer Einstellung baut, lädt und speichert sie. Braucht sie ein anderes Modul, um zu wirken (Branches zu Issues brauchen die Versionsverwaltung), bleibt sie beim Eigentümer und erscheint nur, wenn der Vertrag des anderen Moduls in der Registry bereitsteht (Unterpunkt „Versionsverwaltung“ des Trackers). Gehört sie sichtbar zu einem anderen Modul (Kacheln auf der Willkommensseite), liefert der Eigentümer sie über dessen Vertrag (`TAtlasWelcomeTileInfo.SwitchKey`, `SettingsKey`), und das andere Modul zeigt sie, ohne den Schlüssel zu kennen. Für Abschnitte, die ganz im Knoten eines anderen Moduls stehen sollen, gibt es `IAtlasSettingsContribution` (Gastgeber = Besitzer des Vertrags `HostContract`); fehlt der Gastgeber, baut die Seite den Abschnitt nicht. Die Werte bleiben in jedem Fall gespeichert.
- Größere Abschnitte teilt das Modul wie der Tracker (`Atlas.UI.Tracker.SettingsSection`): Regeln und Zeilen der Tabellen ohne VCL in einer Core-Unit (`Atlas.Core.Tracker.SettingsTables`, mit FPC testbar), je Tabelle bzw. Gruppe ein Teil mit einem View-Record seiner Steuerelemente (`Atlas.UI.Tracker.Settings*`), Bausteine der Zeilen in `SettingsRows`, Haken zur IDE in einer Hakenklasse, die der Provider des Moduls setzt. Der Abschnitt selbst fügt nur zusammen. So bleiben Klassen, Methoden und Units unter den Grenzen der Metriken.
- Dienste von Base über `TAtlasIdeHost` (`Atlas.IDE.Foundation.Host`): laufende bzw. gestartete Sitzung, Meldungsansicht, Warnung, Log, Statusfeld, Compile-Ereignisse. Serverbefehle laufen über `RunCommandAsync` (der eine Hintergrundbefehl), `RunServerCommandAsync` (nebenläufig) und `RunRequestAsync`. Die Antwort kommt im Hauptthread und nur bei offenem Scope (`TAtlasModuleAnswer`). Code eines Moduls läuft nach dem Abmelden in keinem Faden mehr.
- Die Willkommensseite ist das Modul `atlas.welcome` (`Atlas.IDE.Welcome.Composition`); andere Module erreicht sie nur über Verträge (`Atlas.IDE.Welcome.Neighbors`), ihre Menüeinträge kommen über `IAtlasMenuSource`, Kacheln anderer Module über `Atlas.IDE.Contracts.WelcomeTiles`.
- Verträge zwischen Modulen liegen in Base unter `Source/Contracts`: `BuildTools`, `BuildPipeline`, `Tests`, `DebugReport`, `Rules`, `Help` (F1-Hilfe: Base meldet über `IAtlasHelpProvider` Regel, Einstellung oder Fenster unter dem Fokus, das Modul `Atlas.IDE.Help` zeigt die Seite; ohne Modul bleibt F1 bei der IDE), `WelcomeTiles` (Kacheln anderer Module auf der Willkommensseite: das Modul stellt `IAtlasWelcomeTile` bereit, die Seite legt dessen Steuerelement in einen Bereichsrahmen und gibt es frei, sobald das Modul die Kachel zurückzieht; die Seite stellt `IAtlasWelcomeBoard` und `IAtlasWelcomeProjects` bereit), `KnownErrors` (bekannte Fehler beim Exception-Halt, #2460: der Tracker stellt `IAtlasKnownErrors` bereit, sucht im Hintergrund und führt die Knöpfe aus, der Debugger stellt `IAtlasKnownErrorsView` bereit und zeigt die Treffer in der Exception-Leiste; ohne eines der Module bleibt die Leiste unverändert). Base ruft einen Befehl eines Moduls nur über dessen Id auf (`RunModuleCommand`).
- Texte: eigene Tabelle `Atlas.UI.<Modul>.Strings` mit `TAtlas<Modul>TextId` und `TAtlas<Modul>Strings.Text/Fmt` für Texte, die nur das Modul braucht; die Sprache liest jeder Aufruf aus `TAtlasStrings.Language` (Base). Gemeinsam genutzte Texte bleiben in `Atlas.UI.Strings`.
- Tests: jede Testklasse einer Unit des Moduls trägt `[Category('<Package>')]`, z. B. `[Category('Atlas.IDE.Debugger')]`; `Check-TestCoverage` prüft das. Die Tests eines Moduls laufen allein mit `--include:Atlas.IDE.Debugger`.

## Threading-Modell

### Server

Der Ablauf einer Anfrage mit Lese-Thread, `Run`-Thread und Thread-Pool steht oben unter „Ablauf einer Anfrage“. Dazu kommen:

- **Indexaufbau:** je Arbeitsbereich ein Hintergrund-Thread (`TIndexService`). Mehrere Aufbauten (Projekte einer Projektgruppe) laufen über einen gemeinsamen `TIndexScheduler` nacheinander und stufenweise: erst die Projektdateien aller Projekte, dann die Units der Suchpfade, zuletzt die Bibliothek; das aktive Projekt zuerst (#648). Ein neuer Aufbau bricht den laufenden ab und wartet auf ihn.
- **Nachladen einzelner Units:** `EnsureUnit` parst im Thread der Anfrage, ohne globale Sperre und ohne auf den Scheduler zu warten (#617). Eine Sperre schützt nur den Zugriff auf den Builder und zählt seine Nutzer; ein neuer Aufbau gibt den alten Builder erst frei, wenn ihn niemand mehr nutzt.
- **Lesen des Index:** `TSymbolIndex` schützt seine Wörterbücher mit einer `TCriticalSection`, hält sie aber nur für Nachschlagen und für das Kopieren eines Schnappschusses; Durchläufe über alle Symbole laufen auf dem Schnappschuss ohne Sperre (#647). `AddUnit` ersetzt eine Unit vollständig, Leser sehen nie einen halben Stand. `Units` ist ein bis zur nächsten Änderung geteilter, nur lesbarer Schnappschuss; `UnavailableUnits` liefert die Units ohne Datei. Unit-Namen werden außerhalb der Hauptsperre unter einer eigenen Pool-Sperre interniert. Der Namensindex der Import-Vorschläge (`TImportNames`) ist ein unveränderlicher Schnappschuss mit Generation.
- **Dokumente:** Momentaufnahmen aus `IDocumentStore` ändern sich nie und dürfen in jedem Thread gelesen werden.
- **Mehrere Serverinstanzen:** Eine Sperrdatei je Cache (`<cache>.lock`) lässt nur die erste Instanz schreiben; die anderen warten begrenzt und laden deren Stand (#62). Den gemeinsamen Bibliotheks-Cache sperrt ein Aufbau nur zum Schreiben (`IIndexFileSystem.TryLockWrite`, dieselbe Sperrdatei), liest unter der Sperre den aktuellen Stand und ergänzt ihn; so überschreibt kein Projekt die Ergänzungen eines anderen. Nicht geschriebene Caches meldet `TIndexService.OnCacheNotWritten`.

### IDE-Plugin

- **Hauptthread der IDE:** Open Tools API, VCL, Editor-Zeichnungen und alle Einstiegspunkte. Jeder Einstiegspunkt läuft über `TAtlasGuard` (#493), damit keine Ausnahme in die IDE gelangt.
- **Lese-Thread des LSP-Clients:** liest die Ausgabe des Servers und ordnet Antworten zu. Anfragen des Servers (`workspace/applyEdit`, Refresh) und Teilergebnisse kommen dort an; was die IDE anfasst, geht über `TAtlasMainThread.Queue` in den Hauptthread.
- **Datenquellen im Hintergrund:** Vervollständigung, Parameter-Hint und Probleme holen ihre Daten in eigenen Threads (`Atlas.Core.Completion.Internals.Async`); ein Ergebnis gilt nur, wenn die Anfrage noch aktuell ist. Was der Hauptthread synchron braucht, läuft über `TAtlasTimeLimit` in einem Arbeiter-Thread mit hartem Zeitlimit (Standard 200 ms). Was im Zeitlimit-Arbeiter läuft (`Prepare`, Sitzungsfunktion der Quellen), fasst weder VCL noch Open Tools API an und startet keinen Server: Die Quellen bekommen nur eine laufende Sitzung (`RunningSession`); `EnsureSession` und `StopSession` kehren außerhalb des Hauptthreads sofort zurück. Gestartet wird an den Einstiegspunkten im Hauptthread.
- **Einreihen in den Hauptthread:** Im Plugin nur über `TAtlasMainThread` (geprüft durch `Tools/Check-MainThreadQueue.ps1` und die Regel `queue-nil-in-package`, #943), nie `TThread.Queue(nil, …)` oder `TThread.ForceQueue(nil, …)`. Threads mit eigener Lebensdauer, die ihre Einträge beim Beenden selbst entfernen (`Problems.Adapters.Server`, `Build.Target`, `Vcs.Worker`, `Updates.Check`, Watchdog), bleiben bei `Queue` am eigenen Thread mit `RemoveQueuedEvents`.
- **Wächter:** Der Einfrier-Wächter (#501) misst den Hauptthread aus einem eigenen Thread, erst wenn die Nachrichtenschleife nach dem Laden frei ist (die Startzeit samt Anteilen meldet die Composition); die Update-Prüfung (#495) fragt in einem Hintergrund-Thread und liefert per `Queue` am eigenen Thread.
- **Versionsverwaltung (#571):** git und svn laufen nur über `TAtlasBackgroundJobs` (bzw. `TAtlasIdeVcs.Run`) in eigenen Threads; das Ergebnis kommt per `Queue` am eigenen Thread in den Hauptthread. Der Prozessläufer lehnt den Hauptthread ab, beendet den Prozess nach dem Zeitlimit und sobald der Thread beendet wird oder `TAtlasShutdown` signalisiert.
- **Beenden:** `TAtlasShutdown` ist das gemeinsame Abbruchsignal. Jedes Warten in einem Hintergrund-Thread hört darauf, sodass beim Entladen des Packages alle Threads innerhalb einer Sekunde enden. Direkt nach dem Signal hält `TAtlasMainThread.Stop` die Einreihungen in den Hauptthread an.

## Symbolindex

Datenstrukturen (`Atlas.Common.Index.Contract`):

- `TUnitIndex` je Datei: Unit-Name, Dateiname, Zeitstempel, Inhalts-Hash, uses-Listen aus interface und implementation, Symbole, Include-Dateien mit Zeitstempeln (#264, #617), Merker für Bibliothek, kompakte Form und initialization/finalization (#284), Deklarationen aus inaktiven Zweigen getrennt in `Unavailable` (#476) und die Verwendungen der Bezeichner (`Usages`, nach Name sortiert, nur Projekt-Units mit `index.usages`, #492).
- `TIndexSymbol`: Name, Container (umgebender Typ, `''` auf Unit-Ebene), Art (`TIndexSymbolKind`), Bereich der ganzen Deklaration und des Namens, `InInterface`, Sichtbarkeit, Vorfahren (Klassen und Interfaces) bzw. Zieltyp (Helfer), deklarierter Typ mit Typargumenten, Typparameter, Parameterzahl und -typen, Default-Property, virtuell, Include-Datei, Bedingung des `{$IFDEF}`-Zweigs, Signatur als eine Zeile, Direktiven und XMLDoc-Kurztext (#492).
- `TIndexUsage`: Name und alle Stellen in der Unit.
- Rümpfe und lokale Deklarationen stehen nicht im Index. Wer sie braucht (Namensauflösung lokaler Variablen, Kontrollfluss), parst die Datei bei Bedarf.

Speicher (`TSymbolIndex`): ein Wörterbuch Dateischlüssel → `TUnitIndex` und eines Unit-Name → Dateischlüssel, beide unter einer `TCriticalSection`; eine Generation zählt jede Änderung. Die Suche nach Namen und Nachfahren läuft linear über einen Schnappschuss aller Units. Gleiche Zeichenketten legt `TStringPool` nur einmal ab. Übersteigt der geschätzte Bedarf die Speichergrenze (`memoryBudgetMb`, Standard 768 MB, #185), lagert der Index zuerst die Verwendungen aus (sie bleiben im Cache, `TIndexService.UsagesOf` lädt sie nach), dann hält er Bibliotheks-Units und zuletzt Projekt-Units kompakt (nur interface-Symbole).

Namensindex (`TImportNames`, #617): flache Liste der importierbaren Symbole (interface, oberste Ebene) mit einer Zeichenmaske je Name, Projekt-Units vor der Bibliothek. Die Vervollständigung prüft damit Units, die noch nicht in den uses stehen, ohne bei jeder Anfrage alle Symbole unscharf zu vergleichen.

Aufbau (`TIndexBuilder`, `TIndexService`): Der Hintergrund-Thread liest den Cache (zunächst nur die Köpfe), indiziert die Projektdateien und danach referenzierte Units über den `TUnitFileResolver`, rekursiv nur, was in einer uses-Liste vorkommt. Ein Cache-Eintrag gilt weiter, wenn Zeitstempel oder Hash passen; die Symbole einer Unit dekodiert der Builder erst bei der Übernahme. `ApplyChanges` übernimmt Änderungen von außen, `EnsureUnit` indiziert eine Unit nachträglich im aufrufenden Thread.

## Cache-Format

Ablage (`Atlas.Common.Index.CacheDirectory`, #184, #492):

```text
%LOCALAPPDATA%\Atlas\Index\<IDE-Version>\<Projekt-Hash>\index-<Format>.atlasidx
%LOCALAPPDATA%\Atlas\Index\<IDE-Version>\Bibliothek\<Hash>\index-<Format>.atlasidx   (RTL, VCL, FMX je Plattform)
```

`TIndexCache` schreibt ein Binärformat mit String-Tabelle (Formatversion: `TIndexCache.FormatVersion`; das Plugin liest das Format für die Suche der Willkommensseite selbst, `TAtlasWelcomeIndexFiles.cFormatVersion`, #760):

```text
Kopf:       'ATLASIDX' Version Prüfsumme (4 Byte, FNV-1a über alles dahinter)
Texte:      Anzahl, je Text Bytelänge + UTF-8 (Nummer 0 = '')
Units:      Anzahl, je Unit Kopf (Name, Datei, Zeitstempel, Hash, Merker, uses, Includes mit Zeitstempeln,
            Präfixzählung, Hinweise im Unit-Kopf samt Grund ab Format 21, Symbolzahlen), Symbolblock
            mit Länge, Verwendungsblock mit Länge
Symbol:     Verweise in die Texttabelle, Positionen, Merker, Vorfahren, Typen, Parameter, Bedingung,
            Signatur, Direktiven, Kurztext, Verweise des inline-Rumpfs (ab Format 20, #1017)
Verwendung: Name, Anzahl, je Stelle Zeilenabstand zur vorigen und Spalte
```

- Zahlen sind Varints (vorzeichenbehaftete per ZigZag); Texte stehen nur einmal in der Tabelle und teilen sich nach dem Laden eine Instanz.
- `ReadEntries` liest nur die Köpfe. Die Symbole einer Unit dekodiert `Expand` erst, wenn der Builder die Unit übernimmt; Verwendungen bleiben bei knappem Speicher in der Datei.
- Beim Start gilt ein Eintrag, solange Zeitstempel oder Hash zur Datei passen (bei Units mit Includes auch deren Zeitstempel); sonst wird die Datei neu eingelesen.
- Eine falsche Prüfsumme, eine abgeschnittene Datei, eine andere Version oder ein früheres Format (JSON, Zeilenformat, `index-*.json`) verwirft den Cache mit dem Grund im Protokoll (`OnCacheRejected`); der Aufbau liest still neu. Ändert sich `TIndexSymbol`, steigt `FormatVersion`. Die Konstante des Plugins muss mitziehen; `TAtlasWelcomeIndexFilesTests.FormatVersionMatchesServer` prüft das.
- Geschrieben wird nur, wenn etwas neu eingelesen wurde oder Units weggefallen sind. Der Ordner wird auf eine Höchstgröße begrenzt (`index.cacheMaxMb`), am längsten nicht benutzte Caches zuerst (`TIndexCacheHousekeeping`); „Index löschen“ (`atlas.server.clearIndex`) und `--clear-cache` leeren ihn.
- Aufräumen beim Laden eines Projekts (#905): Neben jedem Projekt-Cache stehen `projekt.txt` (Projektdatei, sonst Arbeitsordner) und `benutzt.stamp` (letzte Benutzung, auch beim Bibliotheks-Cache). Caches, deren Herkunft nicht mehr existiert, gehen (`index.removeOrphans`; Caches ohne `projekt.txt` prüfen ihre Projekt-Units und tragen die Herkunft nach; fehlt das Laufwerk, bleibt der Cache), ebenso `index-*.json` im alten Format und `build-*.json` gelöschter Projekte. Caches, die länger als `index.cacheMaxAgeDays` Tage nicht benutzt wurden, gehen auch. Eigene und gesperrte Caches bleiben immer.

## Geplante Zuordnung der Bausteine

Vorschlag, wird mit den jeweiligen Issues verfeinert:

| Baustein | Ort | Begründung |
|---|---|---|
| Dokumentverwaltung, Lexer, Parser, Präprozessor, Symbolindex, Namensauflösung, Prüfregeln, DFM-Parser | `Atlas.Common` | reine Textverarbeitung |
| Delphi-Installationen und Bibliothekspfade aus der Registry (#14, #47) | `Atlas.Windows` | Registry |
| Compiler- und MSBuild-Aufruf (#40) | `Atlas.Windows` | Prozesse, `rsvars.bat` |
| Debug-Adapter, Windows-Debug-API (#75) | `Atlas.Windows` | Windows-API |
| LSP-Methoden (Navigation, Hover, Code-Aktionen …) | `AtlasServer`, Hosted-Features | Fachcode des Servers |
| Einstiegspunkt, Komposition | `AtlasServer`, Shell | Host |
