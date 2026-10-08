# Architektur von BetterDelphiLSP

Entscheidungen mit Begründung stehen im Entscheidungsprotokoll unter [`docs/adr/`](adr/README.md).

Grundlage ist das Konzept „Rollenbasierte Kopplung und Kohäsion“ (Entwurf, Stand 30.09.2026). Dieses Dokument hält fest, wie das Konzept in diesem Projekt angewendet wird. Bei Widersprüchen gilt das Konzept.

## Ausgabeartefakte

| Projekt | Art (Konzept 6.2) | Darf verwenden | Darf nicht verwenden |
|---|---|---|---|
| `BDLsp.Common` | Platform-Package | plattformunabhängige RTL (`System.*`) | Windows (`Winapi.*`, `System.Win.*`), VCL, FMX, `BDLsp.Windows` |
| `BDLsp.Windows` | Platform-Package | RTL, `Winapi.*`, `System.Win.*`, `BDLsp.Common` | VCL, FMX |
| `BetterDelphiLSP` | Anwendung (Host) | beide Packages, RTL, Windows | VCL (Konsolenanwendung) |
| `BDLsp.Tests` | Testprojekt (DUnitX) | alles, was getestet wird | – |

Abhängigkeitsrichtung:

```text
BetterDelphiLSP ──► BDLsp.Windows ──► BDLsp.Common ──► RTL
       │                                   ▲
       └───────────────────────────────────┘
```

Die Regeln für die Packages prüft `Tools/Check-PackageDependencies.ps1` (uses- und requires-Klauseln). Das Skript läuft lokal und in der GitHub Action „Package-Abhängigkeiten“.

## Verzeichnisstruktur

```text
BetterDelphiLSP.groupproj          Projektgruppe (Build-Reihenfolge: Common, Windows, Anwendung, Tests)
Packages/
  BDLsp.Common/
    BDLsp.Common.dpk/.dproj
    Source/<Feature>/              ein Ordner je Platform-Feature, darin optional Rollenordner
  BDLsp.Windows/
    BDLsp.Windows.dpk/.dproj
    Source/<Feature>/
Application/
  BetterDelphiLSP.dpr/.dproj
  Source/
    Foundation/  Core/  Adapters/  Platform/  Features/  Shell/   (Host-Rollen, Konzept 7.2/7.3)
Tests/
  BDLsp.Tests.dpr/.dproj
  Common/  Windows/  Application/  (Tests je Ausgabeartefakt)
  Data/Protocol/                   aufgezeichnete Nachrichtenfolgen für Protokolltests (JSON)
Editors/VSCode/                    minimale VS-Code-Erweiterung (TypeScript), startet den Server
Tools/                             Hilfsskripte
Output/<Plattform>/<Konfiguration>/ Build-Ausgabe (nicht versioniert): Dcu, Dcp, Bpl, Bin
```

Die Anwendung und das Testprojekt binden die Packages statisch ein: Sie finden die DCUs der Packages in `Output/<Plattform>/<Konfiguration>/Dcu/<Package>`. Deshalb müssen die Packages vor der Anwendung gebaut werden; die Projektgruppe regelt das.

## Benennung (Konzept 6.3)

```text
Ausgabeartefakt.Feature.Rolle.Sache
```

- Präfixe der Ausgabeartefakte (Whitelist): `BDLsp.Common`, `BDLsp.Windows`
- Units der Anwendung tragen kein Präfix, z. B. `Shell.Application`
- Units im Wurzelverzeichnis eines Features tragen keinen Rollenbezeichner, z. B. `BDLsp.Common.Product.Version`
- Rollenbezeichner sind reserviert: `Contract`, `Providers`, `Adapters`, `Internals`, `Hosting`, `Composition` (Features) sowie `Foundation`, `Core`, `Shell`, `Adapters`, `Platform` (Host)

## Importregeln

Platform-Features in den Packages (Konzept 8.3) importieren weder Host noch Hosted-Features:

| Importierende Rolle | Darf importieren |
|---|---|
| Contract | eigenes Contract, fremdes Contract |
| Internals | eigenes Contract und Internals, fremdes Contract und Root |
| Providers, Adapters, Root | eigenes Contract, Internals und Root, fremdes Contract und Root |
| Composition | eigenes Contract, Providers, Adapters, Root und Composition, fremdes Contract und Root |

Für die Anwendung gelten die Host-Matrix (8.1) und die Hosted-Feature-Matrix (8.2). Hosted-Features importieren sich nie gegenseitig; feature-übergreifende Abläufe orchestriert der Host (Konzept 11).

## Tests

- Unit-Tests mit DUnitX je Unit in `Tests/<Ausgabeartefakt>/<Feature>/`.
- Protokolltests: `Tests/Data/Protocol/*.json` enthalten Schritte `send` und `expect`; `BDLsp.Common.Lsp.ProtocolReplay` spielt sie gegen den Server ohne Threads ab und vergleicht die Antworten feldweise. Neue Aufzeichnung = neue JSON-Datei, kein Code nötig.
- Fuzzing: zufällig beschädigter Code (fester Startwert) darf den Parser weder abstürzen noch hängen lassen.
- Korpustest: parst RTL und VCL aus `$(BDS)\source` oder dem Ordner in `BDLSP_CORPUS`; ohne beides wird er übersprungen.
- Leistungsmessung mit festen Zielwerten (Syntaxfehler < 200 ms, Gliederung und Faltbereiche < 100 ms).
- Der Parser begrenzt die Verschachtelung auf 256 Ebenen und gibt Bäume iterativ frei, damit kaputter Code keinen Stapelüberlauf auslöst.

## DI-Strategie

Komposition von Hand (keine Container-Bibliothek). Composition-Units tragen deshalb kein Strategie-Suffix. Wird später eine zweite Strategie (z. B. Spring4D) eingeführt, erhalten die Units ein Suffix nach Konzept 7.6.

## Umgesetzte Features

| Feature | Units | Inhalt |
|---|---|---|
| `BDLsp.Common.Logging` (Platform) | `Contract`, `Providers.Logger`, `Providers.StreamSink` | `ILogger` (API) und `ILogSink` (SPI), Logger mit Mindeststufe je Senke, Senke für Datei und stderr |
| `BDLsp.Common.JsonRpc` (Platform) | `Contract`, `Messages`, `StreamTransport`, `LineTransport`, `TracingTransport`, `PendingRequests`, `Watchdog`, `Statistics`, `Dispatcher`, `Connection` | JSON-RPC 2.0 mit LSP-Rahmung (`Content-Length`) über beliebige Streams, Mitschnitt, Verteilung auf Handler, Nachrichtenschleife mit Lese-Thread, nebenläufige Anfragen im Thread-Pool, `$/cancelRequest`, Zeitlimit je Anfrage (`Watchdog`), Meldung unerwarteter Handler-Fehler (`OnRequestFailed`), Antwortzeiten je Methode (`Statistics`) |
| `BDLsp.Common.Documents` (Platform) | `Contract`, `TextDocument`, `FileEncoding`, `Uris`, `Providers.DocumentStore` | Kodierung (UTF-8 mit/ohne BOM, Windows-1252, UTF-16) und Zeilenenden von Dateien erkennen und beim Schreiben erhalten, gemischte Kodierungen im Projekt zählen; geöffnete Dokumente als unveränderliche Momentaufnahmen mit Zeilenindex, Positionen in UTF-16-Codeeinheiten, inkrementelle Änderungen, Speicher je URI mit Ereignissen (Opened, Changed, Saved, Closed); URI ↔ Pfad und eindeutige Dokumentschlüssel (Kodierung, Laufwerksbuchstabe, Groß-/Kleinschreibung, `\\?\`, `.`/`..`) |
| `BDLsp.Common.Pascal` (Platform) | `Contract`, `Lexer`, `SyntaxTree`, `Parser`, `TreeCache`, `Preprocessor`, `IncludeFiles`, `LanguageFeatures` | Eigener rekursiv absteigender Parser (statt DelphiAST) mit vollständigem Syntaxbaum auch bei fehlerhaftem Code (`Error`-Knoten, `Diagnostics`, Wiederaufsetzen an Deklarations-, Mitglieds- und Anweisungsgrenzen). Lexer für Object Pascal: reservierte Wörter, Bezeichner mit `&`, Zahlen (dezimal, `$`, `%`, `&`), Strings auch mehrzeilig, `#`-Zeichen, Kommentare und Direktiven als eigene Token, UTF-16-Positionen, fehlertolerant (`Terminated`, `Unknown`). Präprozessor: `$IFDEF`/`$IF`/`$ELSEIF`/`$ELSE`/`$ENDIF`, `$DEFINE`/`$UNDEF`, Includes mit Positionen je Datei, inaktive Bereiche, vordefinierte Plattformsymbole; gemeinsame Include-Suche für Präprozessor, Index, Abblenden und Verweise (Ordner der Unit, dann Projekt-Suchpfade, dann Bibliothekspfade; `.inc`/`.pas` bei fehlender Endung); Sprachmerkmale mit Mindestversion (Inline-Variablen, Managed Records, mehrzeilige Strings, If-Ausdrücke); gemeinsamer, referenzgezählter Syntaxbaum je Dokumentversion (einmal parsen, überholte Läufe abbrechen) |
| `BDLsp.Common.Projects` (Platform) | `Contract`, `Paths`, `DprojReader`, `UnitResolver`, `Internals.Xml`, `Internals.MSBuild` | `.dproj` für Konfiguration und Plattform auswerten (MSBuild-Bedingungen, `$(…)`-Verweise): Hauptdatei, Defines, Suchpfade, Namespaces, Units mit Pfad; Unit-Namen wie der Compiler zu Dateien auflösen (Projekt, Ordner, Suchpfade, Bibliothek, Namespace-Präfixe); eigener kleiner XML-Leser, da `Xml.XMLDoc` MSXML braucht |
| `BDLsp.Common.Compiler` (Platform) | `Contract`, `OutputParser`, `CommandLine`, `Results` | Compiler-Anbindung (#40): Ausgabe von dcc32/dcc64 und MSBuild in Meldungen mit Fundstelle zerlegen (Schweregrad aus der Meldungsnummer, unabhängig von der Sprache), Aufruf für ein Projekt in einen eigenen Ausgabeordner, letzte Meldungen je Datei; `ICompilerProcess` startet den Compiler |
| `BDLsp.Common.Dfm` (Platform) | `Contract`, `Parser`, `Navigation`, `ComponentRename` | Text-DFM/-FMX (#44) fehlertolerant als Objektbaum lesen (Properties, Ereignisse, Collections, Binärdaten); Sprünge vom Ereignis zur Methode, vom Komponentennamen zum Feld, vom Formular zur Klasse in der Unit daneben; automatisch benannte Ereignis-Handler beim Umbenennen einer Komponente mitziehen (#45) |
| `BDLsp.Common.Mcp` (Platform) | `Server`, `IndexTools`, `CodeTools` | Model Context Protocol (#48) auf dem JSON-RPC-Dispatcher mit Zeilenrahmung (`LineTransport`): `initialize`, `tools/list`, `tools/call`; lesende Werkzeuge auf dem Symbolindex (Symbolsuche, Deklaration, Typhierarchie, Unit-Gliederung, Formularinhalt), Verwendungen, Aufrufhierarchie und Befunde (`CodeTools`) |
| `BDLsp.Common.Configuration` (Platform) | `Contract`, `Parser`, `Internals.JsonTree` | `delphi-lsp.json` (JSONC) lesen und prüfen: Delphi-Version, Sprache, Projekt, Konfiguration, Plattform, Regel-Schweregrade, Ausschlüsse (Globs), Formatierung; Fehler mit Position für Diagnosen |
| `BDLsp.Common.Index` (Platform) | `Contract`, `Extractor`, `SymbolIndex`, `Cache`, `CacheHousekeeping`, `Builder`, `ProjectFiles`, `Service`, `Adapters.DiskFileSystem`, `Adapters.CacheDirectory` | Symbolindex: Deklarationen je Unit mit Position, Art, Container, Vorfahren und uses-Listen (inaktive Zweige ausgeblendet); threadsicherer Speicher mit Suche nach Namen und Nachfahren; JSON-Cache mit Zeitstempel und Hash, atomar geschrieben, gesperrt je Instanz und auf eine Höchstgröße aufgeräumt; Aufbau im Hintergrund, referenzierte Bibliotheks-Units bedarfsweise; Dateiänderungen von außen übernehmen |
| `BDLsp.Common.Semantics` (Fachlogik) | `NameResolver`, `ControlFlow` | Namensauflösung: Bezeichner und Punktketten an einer Position zur Deklaration auflösen (lokale Variablen, Parameter, Self und Klassenmitglieder samt Vorfahren, aktuelle Unit, uses-Reihenfolge, System, Unit-Namen); Typen über Aliase verfolgen; Typnamen aus Sicht einer beliebigen Unit auflösen; einen Baum für viele Aufrufe vorab auswerten (`PinTree`); Kandidatenlisten für die Vervollständigung (sichtbare Namen, Mitglieder einer Kette); Kontrollflussgraph je Routine mit Erreichbarkeit, Dominanz und erreichenden Zuweisungen als Grundlage für flussbasierte Prüfregeln |
| `BDLsp.Common.Rules` (Fachlogik) | `Contract`, `Registry`, `Suppressions`, `Engine`, `Profiles`, `Checker`, `Filter`, `Output`, `Builtin.Unicode`, `Builtin.UnitFiles`, `Builtin.Architecture`, `Builtin.Concurrency` | Prüfregel-Framework: Regel mit Kennung, Standard-Schweregrad und Beschreibung (`IRule`), Treffer mit Korrekturen (`TRuleFix`), Verzeichnis ohne doppelte Kennungen, Schweregrad und Abschalten aus `delphi-lsp.json`, Ausnahmen je Regel (`exclude` mit Globs oder Unit-Namen), Regelprofile, Pfadregeln (`overrides`) und Ausnehmen von Test-Units, Unterdrückung per `// lsp-ignore: regel` und `// lsp-ignore-file: regel`; Konfidenz begrenzt den Schweregrad; Linter ohne Editor mit Filtern und Ausgabe als Text, JSON und SARIF; eingebaute Regeln unter `Builtin` (Unicode-Sicherheit: Bidi-Steuerzeichen, unsichtbare und Steuerzeichen, Bezeichner mit gemischten Schriften; Unit-Name passend zum Dateinamen) |
| `BDLsp.Common.Lsp` (Platform) | `Contract`, `Lifecycle`, `Positions`, `TextDocumentSync`, `SyntaxDiagnostics`, `PullDiagnostics`, `DocumentSymbols`, `FoldingRanges`, `SelectionRanges`, `Definition`, `Hover`, `HoverValues`, `FuzzyMatch`, `LinkedEditing`, `Formatting`, `FormFiles`, `WorkspaceSymbols`, `DocumentHighlights`, `References`, `Rename`, `FileOperations`, `Completion`, `SignatureHelp`, `Hierarchies`, `Implementations`, `InlayHints`, `MessageHandlers`, `CodeLens`, `SemanticTokens`, `DocumentLinks`, `Colors`, `DocWiki`, `Commands`, `Status`, `WatchedFiles`, `InactiveRegions`, `WorkspaceFolders`, `Configuration`, `WorkDoneProgress`, `PublishedMembers`, `Internals.Debouncer`, `Internals.Cancellation`, `Adapters.LogMessageSink` | LSP-Fehlercodes und Konstanten, Lebenszyklus `initialize` → `initialized` → `shutdown` → `exit`, Position/Range, `didOpen`/`didChange`/`didSave`/`didClose`, Syntaxfehler als `publishDiagnostics` mit 100 ms Debouncing im Hintergrundthread, bei Clients mit LSP 3.17 stattdessen Pull-Diagnosen `textDocument/diagnostic` und `workspace/diagnostic` für alle Projektdateien (Ergebnis-Ids, Zeitbudget je Anfrage, Long-Polling, `workspace/diagnostic/refresh`), Gliederung `documentSymbol` (Unit → interface/implementation → Typen mit Mitgliedern, Routinen mit lokalen Deklarationen), Faltbereiche `foldingRange` (Typen, Routinen, Blöcke, Abschnitte, `uses`, `{$REGION}`, Kommentarblöcke), intelligente Auswahl `selectionRange` (Token → umgebende Knoten bis zur Datei), `definition`/`declaration` über die Namensauflösung (Wechsel zwischen Deklaration und Implementierung, Unit-Namen öffnen die Datei), `typeDefinition` zum Typ von Variablen, Feldern und Funktionen, `hover` mit Deklaration und ///-Dokumentation als Markdown (bei RTL- und VCL-Symbolen mit DocWiki-Link passend zur Delphi-Version) (bei Klassen mit published-Properties und Ereignissen samt geerbter), projektweite Symbolsuche `workspace/symbol` (exakt vor Anfang vor Teilstring, höchstens 200 Treffer), Vorkommen `documentHighlight` mit Lese-/Schreibzugriff, projektweite Referenzsuche `references` (auch Ereignis-Handler und Komponentennamen aus der .dfm), Umbenennen `prepareRename`/`rename` projektweit inkl. .dfm (verweigert bei Unit-Namen und fremden Bibliotheken), Vervollständigung `completion` (sichtbare Namen nach Gültigkeitsbereich, Mitglieder nach `.` samt geerbter, Units in `uses`, unscharfe Auswahl, Symbole aus nicht eingebundenen Units mit uses-Eintrag über `additionalTextEdits`), Parameterhilfe `signatureHelp` (alle Überladungen, aktiver Parameter, ///-Dokumentation samt `<param>`), Typhierarchie (Vorfahr und Interfaces, direkte Nachfahren) und Aufrufhierarchie (aufrufende Routinen über die Referenzsuche, aufgerufene über die Namensauflösung im Rumpf), Gehe zu Implementierung `implementation` (Rümpfe in allen Nachfahren bzw. implementierenden Klassen, Nachfahren von Typen, von `inherited` zum Rumpf im Vorfahren), Inlay Hints `inlayHint` (Parameternamen, abgeleitete Typen bei `var X :=`, Endmarkierungen langer Blöcke, schaltbar über `inlayHints`), Code Lens `codeLens`/`codeLens/resolve` (Referenzen, überschriebene Methode, Nachfahren, Message-Handler samt Vorfahren mit derselben Nachricht, auch im Hover), semantische Hervorhebung `semanticTokens/full` und `/range` (Unit, Klasse, Record, Interface, Aufzählung, Typ, Parameter, Variable, Feld, Property, Ereignis, Aufzählungswert, Funktion, Methode; Modifier declaration, readonly, defaultLibrary), anklickbare Verweise `documentLink` (Include- und Ressourcendateien, URLs, Dateinamen in Strings), Farbvorschau `documentColor`/`colorPresentation` (TColor-Hex, `RGB(…)`, benannte und Systemfarben, Rückschreiben im Ausgangsformat), Dateibeobachter über `workspace/didChangeWatchedFiles` (Index aktualisieren, bei Projektdateien neu aufbauen), inaktive `{$IFDEF}`-Bereiche als Hinweise mit Tag `Unnecessary`, Multi-Root-Arbeitsbereiche (`workspaceFolders`, `didChangeWorkspaceFolders`), Log-Senke `window/logMessage`, Laden und Live-Prüfung der `delphi-lsp.json` mit Diagnosen, Editor-Einstellungen über `workspace/didChangeConfiguration` (Datei hat Vorrang), Fortschritt über `$/progress`, Befehle über `workspace/executeCommand` mit Status-Befehl `betterdelphilsp.status` (Index, Speicher, letzter Indexlauf, Antwortzeiten je Methode) |
| `BDLsp.Windows.Console` (Platform) | `StdStreams` | stdin/stdout/stderr als Streams; nach `ReserveOutputForProtocol` landen `Writeln` und `GetStdHandle(STD_OUTPUT_HANDLE)` auf stderr |
| `BDLsp.Windows.Projects` (Platform) | `DelphiInstallation` | Installierte Delphi-Versionen, `RootDir`, Bibliotheks- und Quellpfade je Plattform und `$(BDS)`-Variablen aus der Registry (`ILibraryPathProvider`) |
| `BDLsp.Windows.Compiler` (Platform) | `Adapters.ProcessRunner` | Compiler unsichtbar starten, stdout und stderr über eine Pipe zeilenweise lesen (#40) |
| `BDLsp.Windows.Documents` (Platform) | `PathCanonicalizer` | Kanonische Pfade über `GetFinalPathNameByHandle` (Junctions, Symlinks, subst, 8.3-Namen, lange Pfade) für die Dokumentschlüssel |
| `BDLsp.Windows.Editing` (Platform) | `SystemColors` | Aktuelle Systemfarben (`GetSysColor`) für die Farbvorschau |
| `BDLsp.Windows.Diagnostics` (Platform) | `DebugOutput`, `Adapters.DebugOutputSink`, `StackTrace` | `OutputDebugString`, Log-Senke dafür, Stacktraces für Ausnahmen (`Modul+$Offset`) |
| `Shell` (Host) | `Shell.Application`, `Shell.Composition`, `Shell.CommandLine`, `Shell.Workspace`, `Shell.Linter` | Einstiegspunkt, Kommandozeile, Komposition von Hand, Capabilities; je Arbeitsbereichsordner eigene Konfiguration, eigenes Projekt und eigener Indexaufbau in einen gemeinsamen Symbolindex |

Ablauf einer Anfrage:

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
- Unerwartete Ausnahmen eines Handlers (nicht `EJsonRpcError`) meldet der Dispatcher über `OnRequestFailed`; die Komposition protokolliert Methode, gekürzte Parameter und Stacktrace. Bei einem Absturz nennt das Log die zuletzt verarbeitete Nachricht.
- Endet die Verbindung (`exit`, Eingabe geschlossen), bricht `Run` offene Anfragen ab und wartet höchstens `WorkTimeout` auf laufende.

Features, die Dateien auswerten, lesen Momentaufnahmen aus `IDocumentStore` (`TServerComposition.Documents`) und abonnieren dessen Ereignisse, um nur die geänderte Datei neu zu verarbeiten. Eine Momentaufnahme ändert sich nie und darf auch in nebenläufigen Anfragen gelesen werden.

Neue LSP-Methoden registrieren ihre Handler in `Shell.Composition` am Dispatcher und tragen ihre Capability in `BuildCapabilities` ein.

## Schichten

Innerhalb von `BDLsp.Common` hängen die Features in dieser Richtung voneinander ab (nur nach unten):

```text
Lsp            LSP-Methoden, Capabilities, Positionen
Semantics      Namensauflösung, Kontrollfluss
Index          Symbolindex, Cache, Aufbau
Pascal         Lexer, Präprozessor, Parser, Syntaxbaum
Projects, Configuration, Documents, JsonRpc, Logging
RTL
```

`Lsp` verbindet Protokoll und Fachlogik; die Fachlogik darunter kennt kein JSON-RPC. `Shell` in der Anwendung setzt alles zusammen und ist die einzige Stelle, die Windows-Adapter und Common-Features verbindet.

## Symbolindex

Datenstrukturen (`BDLsp.Common.Index.Contract`):

- `TUnitIndex` je Datei: Unit-Name, Dateiname, Zeitstempel, Inhalts-Hash, uses-Listen aus interface und implementation, Symbole.
- `TIndexSymbol`: Name, Container (umgebender Typ, `''` auf Unit-Ebene), Art (`TIndexSymbolKind`), Bereich der ganzen Deklaration und des Namens, `InInterface`, Vorfahren (Klassen und Interfaces) bzw. Zieltyp (Helfer), deklarierter Typ.
- Sichtbarkeiten, Parameterlisten und Rümpfe stehen nicht im Index. Wer sie braucht (Hover mit published-Properties, Namensauflösung lokaler Variablen), parst die Datei bei Bedarf.

Speicher (`TSymbolIndex`): ein Wörterbuch Dateischlüssel → `TUnitIndex` und eines Unit-Name → Dateischlüssel, beide unter einer `TCriticalSection`. Die Suche nach Namen und Nachfahren läuft linear über alle Symbole; bei den bisherigen Projektgrößen genügt das. `AddUnit` ersetzt den Stand einer Datei vollständig, deshalb sehen Leser nie eine halb aktualisierte Unit.

Aufbau (`TIndexBuilder`, `TIndexService`): ein Hintergrund-Thread liest den Cache, indiziert zuerst die Projektdateien und danach referenzierte Units über den `TUnitFileResolver`. Ein neuer Start bricht den laufenden Aufbau ab und wartet auf ihn. `EnsureUnit` indiziert eine Unit nachträglich im aufrufenden Thread, z. B. für die Namensauflösung.

## Cache-Format

`TIndexCache` schreibt JSON mit kurzen Schlüsseln (Formatversion 2):

```text
{"version":2,"units":[{"u":Unit,"f":Datei,"t":Zeitstempel,"h":Hash,
  "iu":[interface-uses],"mu":[implementation-uses],
  "s":[[Name,Container,Art,L1,C1,L2,C2,SL1,SC1,SL2,SC2,InInterface,[Vorfahren],Typ], ...]}]}
```

- Beim Start gilt ein Eintrag, solange Zeitstempel oder Hash zur Datei passen; sonst wird die Datei neu eingelesen.
- Ein Cache mit anderer Version oder kaputtem JSON wird verworfen. Ändert sich `TIndexSymbol`, steigt `FormatVersion`.
- Geschrieben wird nur, wenn etwas neu eingelesen wurde oder Units weggefallen sind.

## Geplante Zuordnung der Bausteine

Vorschlag, wird mit den jeweiligen Issues verfeinert:

| Baustein | Ort | Begründung |
|---|---|---|
| Dokumentverwaltung, Lexer, Parser, Präprozessor, Symbolindex, Namensauflösung, Prüfregeln, DFM-Parser | `BDLsp.Common` | reine Textverarbeitung |
| Delphi-Installationen und Bibliothekspfade aus der Registry (#14, #47) | `BDLsp.Windows` | Registry |
| Compiler- und MSBuild-Aufruf (#40) | `BDLsp.Windows` | Prozesse, `rsvars.bat` |
| Debug-Adapter, Windows-Debug-API (#75) | `BDLsp.Windows` | Windows-API |
| LSP-Methoden (Navigation, Hover, Code-Aktionen …) | `BetterDelphiLSP`, Hosted-Features | Fachcode des Servers |
| Einstiegspunkt, Komposition | `BetterDelphiLSP`, Shell | Host |
