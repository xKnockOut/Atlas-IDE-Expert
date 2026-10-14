# Architektur von Atlas IDE Expert

Entscheidungen mit Begründung stehen im Entscheidungsprotokoll unter [`docs/adr/`](adr/README.md).

Grundlage ist das Konzept „Rollenbasierte Kopplung und Kohäsion“ (Entwurf, Stand 30.09.2026). Dieses Dokument hält fest, wie das Konzept in diesem Projekt angewendet wird. Bei Widersprüchen gilt das Konzept.

## Ausgabeartefakte

| Projekt | Art (Konzept 6.2) | Darf verwenden | Darf nicht verwenden |
|---|---|---|---|
| `Atlas.Common` | Platform-Package | plattformunabhängige RTL (`System.*`) | Windows (`Winapi.*`, `System.Win.*`), VCL, FMX, `Atlas.Windows` |
| `Atlas.Windows` | Platform-Package | RTL, `Winapi.*`, `System.Win.*`, `Atlas.Common` | VCL, FMX |
| `AtlasServer` | Anwendung (Host) | beide Packages, RTL, Windows | VCL (Konsolenanwendung) |
| `Atlas.IDE.Expert` | Design-Time-Package für RAD Studio (Win32, ADR 0006) | RTL, `Winapi.*`, `System.Win.*`, VCL, `designide` (Open Tools API) | `Atlas.Common`, `Atlas.Windows` (eigenständig, damit die IDE nur ein BPL laden muss) |
| `Atlas.Tests` | Testprojekt (DUnitX) | alles, was getestet wird | – |

Abhängigkeitsrichtung:

```text
AtlasServer ──► Atlas.Windows ──► Atlas.Common ──► RTL
     │                                 ▲
     └─────────────────────────────────┘
```

Die Regeln für die Packages prüft `Tools/Check-PackageDependencies.ps1` (uses- und requires-Klauseln). Das Skript läuft lokal und in der GitHub Action „Package-Abhängigkeiten“.

## Verzeichnisstruktur

```text
Atlas.groupproj          Projektgruppe (Build-Reihenfolge: Common, Windows, Anwendung, IDE-Plugin, Tests)
Packages/
  Atlas.Common/
    Atlas.Common.dpk/.dproj
    Source/<Feature>/              ein Ordner je Platform-Feature, darin optional Rollenordner
  Atlas.Windows/
    Atlas.Windows.dpk/.dproj
    Source/<Feature>/
  Atlas.IDE.Expert/
    Atlas.IDE.Expert.dpk/.dproj
    Source/Core/  Source/UI/  Source/IDE/   (Schichten des Plugins, #406)
Application/
  AtlasServer.dpr/.dproj
  Source/
    Foundation/  Core/  Adapters/  Platform/  Features/  Shell/   (Host-Rollen, Konzept 7.2/7.3)
Tests/
  Atlas.Tests.dpr/.dproj
  Common/  Windows/  Application/  IDE.Expert/  (Tests je Ausgabeartefakt)
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

- Präfixe der Ausgabeartefakte (Whitelist): `Atlas.Common`, `Atlas.Windows`, `Atlas.IDE.Expert`
- Units der Anwendung tragen kein Präfix, z. B. `Shell.Application`
- Units im Wurzelverzeichnis eines Features tragen keinen Rollenbezeichner, z. B. `Atlas.Common.Product.Version`
- Ausnahme Plugin (#406): Die Units von `Atlas.IDE.Expert` heißen nach ihrer Schicht `Atlas.Core.*` (Datenmodell, Matching, LSP-Client; ohne VCL und Open Tools API), `Atlas.UI.*` (Fenster; nur VCL) und `Atlas.IDE.*` (Open Tools API, Tastaturbindung, Einstellungen), darunter `Feature.Rolle.Sache`. `Core` und `UI` verwenden nie `Atlas.IDE.*`, `Core` nie `Atlas.UI.*`; geprüft durch `Tools/Check-PackageDependencies.ps1`. So lassen sich `Core` und `UI` später ohne Codeänderung in ein Runtime-Package auslagern.
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
- Protokolltests: `Tests/Data/Protocol/*.json` enthalten Schritte `send` und `expect`; `Atlas.Common.Lsp.ProtocolReplay` spielt sie gegen den Server ohne Threads ab und vergleicht die Antworten feldweise. Neue Aufzeichnung = neue JSON-Datei, kein Code nötig.
- Fuzzing: zufällig beschädigter Code (fester Startwert) darf den Parser weder abstürzen noch hängen lassen.
- Korpustest: parst RTL und VCL aus `$(BDS)\source` oder dem Ordner in `ATLAS_CORPUS`; ohne beides wird er übersprungen.
- Leistungsmessung mit festen Zielwerten (Syntaxfehler < 200 ms, Gliederung und Faltbereiche < 100 ms).
- Der Parser begrenzt die Verschachtelung auf 256 Ebenen und gibt Bäume iterativ frei, damit kaputter Code keinen Stapelüberlauf auslöst.

## DI-Strategie

Komposition von Hand (keine Container-Bibliothek). Composition-Units tragen deshalb kein Strategie-Suffix. Wird später eine zweite Strategie (z. B. Spring4D) eingeführt, erhalten die Units ein Suffix nach Konzept 7.6.

## Umgesetzte Features

| Feature | Units | Inhalt |
|---|---|---|
| `Atlas.Common.Logging` (Platform) | `Contract`, `Providers.Logger`, `Providers.StreamSink` | `ILogger` (API) und `ILogSink` (SPI), Logger mit Mindeststufe je Senke, Senke für Datei und stderr |
| `Atlas.Common.JsonRpc` (Platform) | `Contract`, `Messages`, `StreamTransport`, `LineTransport`, `TracingTransport`, `PendingRequests`, `Watchdog`, `Statistics`, `Dispatcher`, `Connection` | JSON-RPC 2.0 mit LSP-Rahmung (`Content-Length`) über beliebige Streams, Mitschnitt, Verteilung auf Handler, Nachrichtenschleife mit Lese-Thread, nebenläufige Anfragen im Thread-Pool, `$/cancelRequest`, Zeitlimit je Anfrage (`Watchdog`), Meldung unerwarteter Handler-Fehler (`OnRequestFailed`), Antwortzeiten je Methode (`Statistics`) |
| `Atlas.Common.Documents` (Platform) | `Contract`, `TextDocument`, `FileEncoding`, `Uris`, `Providers.DocumentStore` | Kodierung (UTF-8 mit/ohne BOM, Windows-1252, UTF-16) und Zeilenenden von Dateien erkennen und beim Schreiben erhalten, gemischte Kodierungen im Projekt zählen; geöffnete Dokumente als unveränderliche Momentaufnahmen mit Zeilenindex, Positionen in UTF-16-Codeeinheiten, inkrementelle Änderungen, Speicher je URI mit Ereignissen (Opened, Changed, Saved, Closed); URI ↔ Pfad und eindeutige Dokumentschlüssel (Kodierung, Laufwerksbuchstabe, Groß-/Kleinschreibung, `\\?\`, `.`/`..`) |
| `Atlas.Common.Pascal` (Platform) | `Contract`, `Lexer`, `SyntaxTree`, `Parser`, `TreeCache`, `Preprocessor`, `IncludeFiles`, `LanguageFeatures`, `XmlDoc` | Eigener rekursiv absteigender Parser (statt DelphiAST) mit vollständigem Syntaxbaum auch bei fehlerhaftem Code (`Error`-Knoten, `Diagnostics`, Wiederaufsetzen an Deklarations-, Mitglieds- und Anweisungsgrenzen). Lexer für Object Pascal: reservierte Wörter, Bezeichner mit `&`, Zahlen (dezimal, `$`, `%`, `&`), Strings auch mehrzeilig, `#`-Zeichen, Kommentare und Direktiven als eigene Token, UTF-16-Positionen, fehlertolerant (`Terminated`, `Unknown`). Präprozessor: `$IFDEF`/`$IF`/`$ELSEIF`/`$ELSE`/`$ENDIF`, `$DEFINE`/`$UNDEF`, Includes mit Positionen je Datei, inaktive Bereiche, vordefinierte Plattformsymbole; gemeinsame Include-Suche für Präprozessor, Index, Abblenden und Verweise (Ordner der Unit, dann Projekt-Suchpfade, dann Bibliothekspfade; `.inc`/`.pas` bei fehlender Endung); Sprachmerkmale mit Mindestversion (Inline-Variablen, Managed Records, mehrzeilige Strings, If-Ausdrücke); gemeinsamer, referenzgezählter Syntaxbaum je Dokumentversion (einmal parsen, überholte Läufe abbrechen); ///-Dokumentation nach Abschnitten (summary, param, returns, exception, remarks; #405, #427) |
| `Atlas.Common.Projects` (Platform) | `Contract`, `Paths`, `DprojReader`, `GroupReader`, `UnitResolver`, `Internals.Xml`, `Internals.MSBuild` | `.dproj` für Konfiguration und Plattform auswerten (MSBuild-Bedingungen, `$(…)`-Verweise): Hauptdatei, Defines, Suchpfade, Namespaces, Units mit Pfad; Projekte einer `.groupproj`; Unit-Namen wie der Compiler zu Dateien auflösen (Projekt, Ordner, Suchpfade, Bibliothek, Namespace-Präfixe); eigener kleiner XML-Leser, da `Xml.XMLDoc` MSXML braucht |
| `Atlas.Common.Diagnostics` (Platform) | `MapFile`, `Contract`, `Anonymizer`, `RequestScope`, `Providers.Log`, `Adapters.LogFolder` | Detaillierte Map-Datei des Linkers lesen (#282): Offsets aus Stacktraces (`Modul+$Offset`) in Unit, Routine und Zeile auflösen; `Atlas.Windows.Diagnostics.StackTrace` hängt das Ergebnis an jede Zeile des Absturzprotokolls. Anonymisiertes Diagnoselog (#647): je Anfrage eine Zeile mit Dauer, Wartezeit, Ergebnis mit Grundcode, Dokument als Kurz-ID (`doc#4`) mit Version, Länge und Prüfsumme, Position als Zahlen, Kontext und Indexzustand; Kurz-IDs statt Pfaden und Namen (RTL/VCL erkannt am Bibliothekspfad), Filter vor dem Schreiben (Laufwerk, `\`, `/`, `@`, Delphi-Endungen, Benutzer- und Rechnername verwerfen die Zeile und zählen mit), Anfragebereich je Thread für Grundcodes der Features, Tagesdateien je Prozess mit Aufbewahrung und Laufmarken für Läufe ohne Ende |
| `Atlas.Common.Compiler` (Platform) | `Contract`, `OutputParser`, `CommandLine`, `Results` | Compiler-Anbindung (#40): Ausgabe von dcc32/dcc64 und MSBuild in Meldungen mit Fundstelle zerlegen (Schweregrad aus der Meldungsnummer, unabhängig von der Sprache), Aufruf für ein Projekt in einen eigenen Ausgabeordner, letzte Meldungen je Datei; `ICompilerProcess` startet den Compiler |
| `Atlas.Common.Dfm` (Platform) | `Contract`, `Parser`, `Navigation`, `ComponentRename`, `FormModel`, `BinaryForm`, `FormInfo` | Text-DFM/-FMX (#44) fehlertolerant als Objektbaum lesen (Properties, Ereignisse, Collections, Binärdaten); Sprünge vom Ereignis zur Methode, vom Komponentennamen zum Feld, vom Formular zur Klasse in der Unit daneben; automatisch benannte Ereignis-Handler beim Umbenennen einer Komponente mitziehen (#45); Formularmodell verknüpft Objekte, Ereignisse und Modulverweise mit Feldern und Methoden der Unit, erkennt binäre Formulare (#267); binäre Formulare (TPF0) im Speicher wie `ObjectBinaryToText` in Text umwandeln, damit alle DFM-Funktionen sie lesen, und auf Befehl als Text-DFM speichern (#122); gesetzte Werte einer Komponente für Hover über Formularfelder und `get_dfm_info` (#126, nur die eigene Formulardatei) |
| `Atlas.Common.Mcp` (Platform) | `Server`, `IndexTools`, `CodeTools`, `IdeEdits` | Model Context Protocol (#48) auf dem JSON-RPC-Dispatcher mit Zeilenrahmung (`LineTransport`): `initialize`, `tools/list`, `tools/call`; lesende Werkzeuge auf dem Symbolindex (Symbolsuche, Deklaration, Typhierarchie, Unit-Gliederung, Formularinhalt, Komponenteninfo mit Properties, Ereignissen, Palettenseite und Package), Verwendungen, Aufrufhierarchie und Befunde (`CodeTools`); bei laufender IDE gehen Schreibaufrufe für offene Dateien an den Eingang des Plugins (`IdeEdits`, #397) |
| `Atlas.Common.Configuration` (Platform) | `Contract`, `Parser`, `Internals.JsonTree` | `atlas.json` (JSONC) lesen und prüfen: Delphi-Version, Sprache, Projekt, Konfiguration, Plattform, Regel-Schweregrade, Ausschlüsse (Globs), Formatierung; Fehler mit Position für Diagnosen |
| `Atlas.Common.Index` (Platform) | `Contract`, `Extractor`, `SymbolIndex`, `Cache`, `CacheHousekeeping`, `Builder`, `ProjectFiles`, `Scheduler`, `Service`, `Adapters.DiskFileSystem`, `Adapters.CacheDirectory` | Symbolindex: Deklarationen je Unit mit Position, Art, Container, Vorfahren und uses-Listen (inaktive Zweige ausgeblendet); threadsicherer Speicher mit Suche nach Namen und Nachfahren; binärer Cache mit String-Tabelle, Zeitstempel und Hash, Symbole erst bei Bedarf dekodiert, atomar geschrieben, gesperrt je Instanz und auf eine Höchstgröße aufgeräumt; Aufbau im Hintergrund in Stufen (Projekt, Suchpfade, Bibliothek), mehrere Projekte einer Gruppe nacheinander, aktives zuerst; referenzierte Bibliotheks-Units bedarfsweise; Dateiänderungen von außen übernehmen |
| `Atlas.Common.Semantics` (Fachlogik) | `NameResolver`, `ControlFlow` | Namensauflösung: Bezeichner und Punktketten an einer Position zur Deklaration auflösen (lokale Variablen, Parameter, Self und Klassenmitglieder samt Vorfahren, aktuelle Unit, uses-Reihenfolge, System, Unit-Namen); Typen über Aliase verfolgen; Ausbaustufe 2: Überladungen nach Argumentzahl und -typen (bei Gleichstand alle über `ResolveAll`), Generics mit eingesetzten Typargumenten, Class/Record Helper (auch für `string`), `with`, Typinferenz für Inline-Variablen, Sichtbarkeit und Ausdrücke als Empfänger (`Foo(1).Bar`, `L[i].Bar`, `(X as T).Bar`); Typnamen aus Sicht einer beliebigen Unit auflösen; einen Baum für viele Aufrufe vorab auswerten (`PinTree`); Kandidatenlisten für die Vervollständigung (sichtbare Namen, Mitglieder einer Kette); Kontrollflussgraph je Routine mit Erreichbarkeit, Dominanz und erreichenden Zuweisungen als Grundlage für flussbasierte Prüfregeln |
| `Atlas.Common.Rules` (Fachlogik) | `Contract`, `Registry`, `Suppressions`, `Engine`, `Profiles`, `Checker`, `Filter`, `Output`, `Builtin.Unicode`, `Builtin.Architecture`, `Builtin.Concurrency`, `Builtin.Flow`, `Builtin.Unused`, `Builtin.Declarations`, `Builtin.Inheritance`, `Builtin.Capture`, `Builtin.Components`, `Builtin.FormFields`, `Builtin.Security`, `Builtin.DataBinding`, `Builtin.DfmProperties`, `Builtin.SlashCommands`, `ChangedFiles` | Prüfregel-Framework: Regel mit Kennung, Standard-Schweregrad und Beschreibung (`IRule`), Treffer mit Korrekturen (`TRuleFix`), Verzeichnis ohne doppelte Kennungen, Schweregrad und Abschalten aus `atlas.json`, Ausnahmen je Regel (`exclude` mit Globs oder Unit-Namen), Regelprofile, Pfadregeln (`overrides`) und Ausnehmen von Test-Units, Unterdrückung per `// lsp-ignore: regel` und `// lsp-ignore-file: regel`; Konfidenz begrenzt den Schweregrad; Linter ohne Editor mit Filtern und Ausgabe als Text, JSON und SARIF; eingebaute Regeln unter `Builtin` (Unicode-Sicherheit: Bidi-Steuerzeichen, unsichtbare und Steuerzeichen, Bezeichner mit gemischten Schriften; Abgleich von Formularfeldern und Objekten der .dfm/.fmx über `TRuleContext.FormText`, #123; Sicherheitsregeln für SQL-Injection (#270), Befehlsinjektion, Pfad-Traversal, schwache Kryptografie, TLS-Prüfung, http:// und Random, #149; Datenbindung der Formulardatei und Zugriff auf Controls fremder Formulare, #151; Eigenschaftsregeln aus `dfmPropertyRules` für Komponenten-Properties mit default-Werten aus der Klassendeklaration, #309) |
| `Atlas.Common.Lsp` (Platform) | `Contract`, `Lifecycle`, `Positions`, `TextDocumentSync`, `SyntaxDiagnostics`, `PullDiagnostics`, `DocumentSymbols`, `FoldingRanges`, `SelectionRanges`, `Definition`, `Hover`, `HoverTypes`, `HoverValues`, `FuzzyMatch`, `LinkedEditing`, `Formatting`, `FormFiles`, `WorkspaceSymbols`, `DocumentHighlights`, `References`, `Rename`, `Completion`, `CompletionEnums`, `SignatureHelp`, `Hierarchies`, `Implementations`, `InlayHints`, `MessageHandlers`, `CodeLens`, `SemanticTokens`, `DocumentLinks`, `Colors`, `DocWiki`, `CompilerDirectives`, `Commands`, `Status`, `QualifiedNames`, `StringLiteralCommands`, `WinApiDocs`, `KeywordReference`, `WatchedFiles`, `InactiveRegions`, `WorkspaceFolders`, `IdeProject`, `Configuration`, `WorkDoneProgress`, `PublishedMembers`, `Internals.Debouncer`, `Internals.Cancellation`, `Adapters.LogMessageSink` | LSP-Fehlercodes und Konstanten, Lebenszyklus `initialize` → `initialized` → `shutdown` → `exit`, Position/Range, `didOpen`/`didChange`/`didSave`/`didClose`, Syntaxfehler als `publishDiagnostics` mit 100 ms Debouncing im Hintergrundthread, bei Clients mit LSP 3.17 stattdessen Pull-Diagnosen `textDocument/diagnostic` und `workspace/diagnostic` für alle Projektdateien (Ergebnis-Ids, Zeitbudget je Anfrage, Long-Polling, `workspace/diagnostic/refresh`), Gliederung `documentSymbol` (Unit → interface/implementation → Typen mit Mitgliedern, Routinen mit lokalen Deklarationen), Faltbereiche `foldingRange` (Typen, Routinen, Blöcke, Abschnitte, `uses`, `{$REGION}`, Kommentarblöcke), intelligente Auswahl `selectionRange` (Token → umgebende Knoten bis zur Datei), `definition`/`declaration` über die Namensauflösung (Wechsel zwischen Deklaration und Implementierung, Unit-Namen öffnen die Datei), `typeDefinition` zum Typ von Variablen, Feldern und Funktionen, `hover` mit Deklaration und ///-Dokumentation als Markdown (bei RTL- und VCL-Symbolen mit DocWiki-Link passend zur Delphi-Version; über Compiler-Direktiven Kurztext und DocWiki-Link, ebenso über seltenen Schlüsselwörtern und Direktiven) (bei Klassen mit published-Properties und Ereignissen samt geerbter), für den Atlas-Tooltip zusätzlich Art, Herkunft, Fundort, Typverweise der Deklaration und Vererbungskette (#588); Hover und Referenzen lesen nicht geöffnete Dateien selbst, projektweite Symbolsuche `workspace/symbol` (exakt vor Anfang vor Teilstring, höchstens 200 Treffer), Vorkommen `documentHighlight` mit Lese-/Schreibzugriff, projektweite Referenzsuche `references` (auch Ereignis-Handler und Komponentennamen aus der .dfm), Umbenennen `prepareRename`/`rename` projektweit inkl. .dfm (verweigert bei Unit-Namen und fremden Bibliotheken), Vervollständigung `completion` (sichtbare Namen nach Gültigkeitsbereich, Mitglieder nach `.` samt geerbter, Units in `uses`, unscharfe Auswahl, Symbole aus nicht eingebundenen Units mit uses-Eintrag über `additionalTextEdits`, Direktiven nach `{$` und Warnungsbezeichner nach `{$WARN`, Werte der erwarteten Aufzählung nach `:=`, `=`, `<>` und in `case`-Zweigen, Mengenelemente in `[…]` mit Häkchen für vorhandene, #448; am Anfang eines `case`-Zweigs zuerst „Alle Werte einfügen“ bzw. „Fehlende Werte ergänzen (n)“ über `Atlas.Common.Editing.CaseCompletion`, #449; unbekannter Name im Rumpf einer Routine: lokale Variable, Inline-Variable, Feld oder Konstante anlegen mit abgeleitetem Typ über `Atlas.Common.Editing.DeclareUnknown`, #471; in einer Klassendeklaration fehlende Methoden der Interfaces aus der Vorfahrenliste mit Deklaration im Abschnitt nach `completion.interfaceSection` und Rumpf über `Atlas.Common.Editing.InterfaceStubs` und `TNameResolver.MissingInterfaceMembers`, #466), Parameterhilfe `signatureHelp` (alle Überladungen, aktiver Parameter, ///-Dokumentation samt `<param>`), Typhierarchie (Vorfahr und Interfaces, direkte Nachfahren) und Aufrufhierarchie (aufrufende Routinen über die Referenzsuche, aufgerufene über die Namensauflösung im Rumpf), Gehe zu Implementierung `implementation` (Rümpfe in allen Nachfahren bzw. implementierenden Klassen, Nachfahren von Typen, von `inherited` zum Rumpf im Vorfahren), Inlay Hints `inlayHint` (Parameternamen, abgeleitete Typen bei `var X :=`, Endmarkierungen langer Blöcke, schaltbar über `inlayHints`), Code Lens `codeLens`/`codeLens/resolve` (Referenzen, überschriebene Methode, Nachfahren, Message-Handler samt Vorfahren mit derselben Nachricht, auch im Hover), semantische Hervorhebung `semanticTokens/full` und `/range` (Unit, Klasse, Record, Interface, Aufzählung, Typ, Parameter, Variable, Feld, Property, Ereignis, Aufzählungswert, Funktion, Methode; Modifier declaration, readonly, defaultLibrary), anklickbare Verweise `documentLink` (Include- und Ressourcendateien, URLs, Dateinamen in Strings), Farbvorschau `documentColor`/`colorPresentation` (TColor-Hex, `RGB(…)`, benannte und Systemfarben, Rückschreiben im Ausgangsformat), Dateibeobachter über `workspace/didChangeWatchedFiles` (Index aktualisieren, bei Projektdateien neu aufbauen), inaktive `{$IFDEF}`-Bereiche als Hinweise mit Tag `Unnecessary`, Multi-Root-Arbeitsbereiche (`workspaceFolders`, `didChangeWorkspaceFolders`), Projektkontext aus der IDE (`atlas/projectContext`, #396: Konfiguration, Plattform, Symbole, Suchpfade, Namespaces, Bibliothekspfade und Delphi-Version der IDE haben Vorrang vor der `.dproj`), Log-Senke `window/logMessage`, Laden und Live-Prüfung der `atlas.json` mit Diagnosen, Editor-Einstellungen über `workspace/didChangeConfiguration` (Datei hat Vorrang), Fortschritt über `$/progress`, Befehle über `workspace/executeCommand` mit Status-Befehl `atlas.server.status` (Index, Speicher, letzter Indexlauf, Antwortzeiten je Methode) und `atlas.server.qualifiedName` (voll qualifizierter Name des Symbols unter dem Cursor, auch als MCP-Werkzeug `qualified_name`), `atlas.server.plainText` und `atlas.server.textToLiteral` (Klartext und String-Literal umwandeln) |
| `Atlas.Windows.Console` (Platform) | `StdStreams` | stdin/stdout/stderr als Streams; nach `ReserveOutputForProtocol` landen `Writeln` und `GetStdHandle(STD_OUTPUT_HANDLE)` auf stderr |
| `Atlas.Windows.Projects` (Platform) | `DelphiInstallation` | Installierte Delphi-Versionen, `RootDir`, Bibliotheks- und Quellpfade je Plattform und `$(BDS)`-Variablen aus der Registry (`ILibraryPathProvider`) |
| `Atlas.Windows.Compiler` (Platform) | `Adapters.ProcessRunner` | Compiler unsichtbar starten, stdout und stderr über eine Pipe zeilenweise lesen (#40) |
| `Atlas.Windows.Documents` (Platform) | `PathCanonicalizer` | Kanonische Pfade über `GetFinalPathNameByHandle` (Junctions, Symlinks, subst, 8.3-Namen, lange Pfade) für die Dokumentschlüssel |
| `Atlas.Windows.Editing` (Platform) | `SystemColors` | Aktuelle Systemfarben (`GetSysColor`) für die Farbvorschau |
| `Atlas.Windows.Diagnostics` (Platform) | `DebugOutput`, `Adapters.DebugOutputSink`, `StackTrace`, `ProcessInfo` | `OutputDebugString`, Log-Senke dafür, Stacktraces für Ausnahmen (`Modul+$Offset`), Threadzahl sowie Benutzer- und Rechnername für den Filter des Diagnoselogs |
| `Atlas.Core.Lsp` (Plugin) | `Client`, `Session`, `TextChanges`, `WorkspaceEdits`, `Adapters.ServerProcess` | Schlanker LSP-Client (Rahmung, Antwortzuordnung, Zeitlimit, Server-Anfragen mit null beantworten), Sitzung mit Dokumentabgleich (didOpen, didChange nur mit dem geänderten Bereich, #395; nach einem Serverneustart alle Dokumente sofort wieder öffnen, #393), Änderungen außerhalb der IDE als `workspace/didChangeWatchedFiles`, Hover, Definition, prepareRename und Rename; `workspace/applyEdit` des Servers (Antwort später über `Respond`, #397); WorkspaceEdits lesen (`changes` und `documentChanges`, Dateioperationen gezählt) und gegen den Ausgangstext ordnen und anwenden (#397); Pfad ↔ URI, Editorspalte → Zeichenindex; Serverprozess mit Pipes und Lese-Thread |
| `Atlas.Core.Files` (Plugin) | `ExternalChanges`, `TextDiff`, `TextFile`, `EditInbox`, `WatchedChanges`, `Adapters.FolderWatcher` | Extern geänderte offene Dateien neu laden (#536); Dateiänderungen außerhalb der IDE (#395): Ordner der Projekte (Git-Arbeitsverzeichnis, sonst Projektordner) mit `ReadDirectoryChangesW` beobachten, Ereignisse je Datei zusammenfassen und nach 300 ms Ruhe an den Server geben; Quelltext auf der Platte in seiner Kodierung (UTF-8 mit/ohne BOM, UTF-16, ANSI) ändern (#397); Eingang für schreibende MCP-Werkzeuge (`ide-edits\<pid>`, Übernahme durch Umbenennen, `Atlas.IDE.Files.EditInbox` ändert den Puffer und speichert, #397) |
| `Atlas.Core.Projects` / `Atlas.IDE.Projects` (Plugin) | `Context` | Projektkontext für den Server (#396): Konfiguration und Plattform jedes Projekts der Gruppe, `DCC_Define`, `DCC_UnitSearchPath` und `DCC_Namespace` der aktiven Konfiguration für die aktive Plattform (mit geerbten Werten, auch ungespeichert), Bibliothekspfade und Version der laufenden IDE; roh in `initialize` (`initializationOptions.projectContexts`) und bei Änderung als `atlas/projectContext`, höchstens einmal je Sekunde geprüft |
| `Atlas.Core.Completion` (Plugin) | `Contract`, `Composite`, `Internals.Async`, `Providers.Server`, `Providers.Fixed` | Datenquelle der Vervollständigung (#408): Kontext und Eintrag, `IAtlasCompletionProvider` mit Senke (Teilmengen, genau ein `Complete`, nach `Cancel` nichts mehr), Zusammenführen mehrerer Quellen, Quelle Server (Abgleich im Hauptthread, Anfrage im Hintergrund, LSP-Einträge übersetzen), feste Testdaten mit optionaler Verzögerung; Details zum gewählten Eintrag über `IAtlasCompletionResolver` (Server: `completionItem/resolve`, `data.atlas`) |
| `Atlas.Core.Completion` (Plugin, Ablauf) | `Matching`, `Controller`, `Sets` | Filtern und Sortieren im Plugin (#409: genauer Name, Anfang, Wortanfänge/CamelCase, Teilstring, Teilfolge; bei Gleichstand Reihenfolge der Quelle); Ablauf ohne Fenster (#410, #414): Start, Einträge aus Hintergrund-Threads per `TThread.Queue` in den Hauptthread, Neu-Filtern beim Tippen, Tasten, Übernahme, Schließen; Anzeige über `IAtlasCompletionView`; Mengenmodus (#448): Leertaste hakt ab, Enter schreibt die ganze Menge `[a, b]`; stehen nur Deklarationen eines unbekannten Namens in der Liste (#471), ist nichts gewählt und Enter gehört dem Editor; „Interface implementieren“ (#466) nutzt die Liste mit Kontrollkästchen (`Batch`) und fasst beim Übernehmen die Einfügungen an derselben Stelle zusammen, Hinweise (`Hint`) stehen oben und sind nie vorgewählt |
| `Atlas.Core.Style` (Plugin) | `Color`, `Palette`, `Syntax` | Aussehen ohne VCL (#411): Farbmathematik im TColor-Format (Mischen wie rgba, HSL, Leuchtdichte und Kontrast nach WCAG), Farbrollen hell/dunkel nach dem Entwurf mit festem Akzent `#0D5EAF`/`#5B9BE6` und Badge-Farben je Art (Kontrast ≥ 4,5 : 1 per Test), einfache Syntaxfärbung für Deklarationen und Signaturen |
| `Atlas.Core.Completion.Presentation` (Plugin) | – | Darstellung eines Eintrags (#420, #421): Badge (fn, pr, pp, fd, ev, co, ty, va, un, kw, sn; Methode nach Signatur), Detail, Tags (`+ Unit` bei uses-Ergänzung, deprecated, constructor/destructor), Trefferpositionen nach den Regeln des Matchings |
| `Atlas.UI.Popup` / `Atlas.UI.Completion` (Plugin) | `Window`, `Styled`, `Popup`, `Details` | Fenster ohne Fokus (#410: `WS_EX_NOACTIVATE`, `MA_NOACTIVATE`, Zeigen mit `SWP_NOACTIVATE`) mit Akzentrahmen und runden Ecken (Windows 11 über DWM, sonst Fensterregion), Editor- und UI-Schrift; eingefärbter Code-Text mit aktivem Bereich; Vervollständigungs-Popup als virtuelle Liste (#413) mit Badge, Name mit hervorgehobenen Treffern, rechtsbündig Detail und Tags, Fußzeile `n von m`, schmaler Scrollleiste, Mausauswahl und Mausrad; Detailpanel im selben Fenster (Trennlinie, abgesetzte Fläche, rechts bzw. ohne Platz links der Liste; Breite und Höhe wachsen in einer Sitzung nur); Platzierung unter bzw. über dem Caret im Arbeitsbereich des Monitors |
| `Atlas.IDE.Editor` / `Atlas.IDE.Completion` (Plugin) | `Buffer`, `Editor`, `WorkspaceEdit`, `Rename` | WorkspaceEdits in die Puffer übernehmen (je Datei ein Rückgängig-Schritt; nicht geöffnete Dateien öffnen oder auf die Platte schreiben; erst alles prüfen, dann ändern) und „Symbol umbenennen…“ (#397); Editorpuffer lesen (ganz, eine Zeile), Tabulatorweite, LSP-Position → Byte-Offset; Vervollständigung im Editor: Präfix und Caret am Cursor, Tastaturbindung für ↑ ↓ Bild↑ Bild↓ Pos1 Ende Enter Tab Esc nur bei offenem Popup, Neu-Filtern über `EditorViewModified` und Zeitgeber, Schließen bei Fokusverlust, Scrollen, Tab-Wechsel oder Verlassen des Worts (#414), Übernahme samt uses-Ergänzung als ein Undo-Schritt |
| `Atlas.Core.Signature` / `Atlas.UI.Signature` / `Atlas.IDE.Signature` (Plugin) | `Contract`, `CallScanner`, `Controller`, `Providers.Server`, `Hint`, `Editor` | Parameter-Hint (#436, #437, #440): Aufruf am Caret lokal finden und aktiven Parameter zählen (Strings, Kommentare, `[...]`, innere Aufrufe und `if (` ausgenommen), Signaturen über `textDocument/signatureHelp` im Hintergrund, automatischer Wechsel zur passenden Überladung und Alt+↑/↓, Hint ohne Fokus mit eingefärbten Signaturen, aktivem Parameter auf Akzentfläche, Doku-Zeile und Fehlerzustand bei zu vielen Argumenten (#439), unter bzw. bei offenem Popup über der Zeile; schließt beim Verlassen des Aufrufs, Esc, Fokusverlust |
| `Atlas.Core.Problems` / `Atlas.IDE.Problems` (Plugin) | `Contract`, `Store`, `Painter`, `MessageList`, `Controller` | Probleme im Editor (#398): Diagnosen des Servers per Pull (`textDocument/diagnostic` für abgeglichene Dateien, `workspace/diagnostic` mit Long-Polling für alle anderen, neu holen nach `workspace/diagnostic/refresh`), Speicher je Datei mit mitwandernden Markierungen (Zeilen vor und hinter der Änderung bleiben bzw. verschieben sich, in der Änderung blass) und Compilermeldungen, die bis zum nächsten Compile mitwandern und blass werden; Wellenlinien nach Schweregrad (PaintLine), Probleme oben im Hover-Tooltip, Liste im Meldungsfenster (Gruppe „Atlas-Probleme“, ohne dcc, höchstens 1000), didClose für in der IDE geschlossene Dateien |
| `Atlas.Core.InlayHints` / `Atlas.IDE.InlayHints` (Plugin) | `Store`, `Editor` | Inlay-Hints (#401, ARG-040, Einstellung „Inlay-Hints“, standardmäßig aus): Parameternamen vor Literal-Argumenten aus `textDocument/inlayHint`; Zwischenspeicher je Datei und Textstand, geholt nur für fehlende sichtbare Zeilen (mit 20 Zeilen Rand) 300 ms nach der letzten Änderung; startet keinen Server. Gezeichnet als Marken hinter dem Zeilenende (`INTACodeEditorEvents`, `plsEndPaint`), weil der Editor keinen eingeschobenen Text kennt; Datei, Undo und Cursor bleiben unberührt |
| `Atlas.Core.Results` / `Atlas.UI.Results` / `Atlas.IDE.Results` (Plugin) | `Model`, `Frame`, `RenamePreview`, `Window`, `Commands` | Ergebnisfenster (#400): andockbares IDE-Fenster „Atlas-Ergebnisse“ (`INTAServices.CreateDockableForm`) mit Referenzen (samt Formularen) und Implementierungen nach Unit gruppiert, Aufrufern, Aufrufen, Vorfahren und Nachfahren als Baum mit Nachladen beim Aufklappen; Doppelklick oder Enter springt. Symbolsuche (`workspace/symbol`) im Fenster der Befehlspalette, Einträge 150 ms nach der letzten Eingabe neu geholt. Umbenennen zeigt vorher alle betroffenen Zeilen vorher und nachher. Befehle im Menü Atlas und in der Befehlspalette |
| `Atlas.Core.Editor` / `Atlas.IDE.Commands` (Plugin) | `Selection`, `SlashTrigger`, `Editor`, `Bindings`, `ContextMenu` | Bedienung im Editor (#399): Code-Aktionen (`textDocument/codeAction`) im Fenster der Befehlspalette in der Reihenfolge des Servers, bevorzugte zuerst; die gewählte ändert die Puffer über `Atlas.IDE.Editor.WorkspaceEdit` und führt dann ihren Befehl aus (`atlas.copyText` in die Zwischenablage, sonst `workspace/executeCommand`). Auswahl erweitern/verkleinern über `textDocument/selectionRange` (Kette am Anker, dem Cursor beim ersten Erweitern), Gehe zu Typdefinition, qualifizierten Namen kopieren (`atlas.server.qualifiedName`). Schnellbefehle mit `/` nach Enter und `///`-Gerüste: Nach jeder Änderung prüft `SlashTrigger` die Cursorzeile, dann `textDocument/onTypeFormatting` per `ForceQueue`. Eine `IOTAKeyboardBinding` für alle Editor-Kürzel mit Konfliktprüfung (#494); Untermenü *Atlas* im Kontextmenü jedes Editorfensters (`EditorLocalMenu`, `FreeNotification`); dieselben Befehle im Menü Atlas und in der Befehlspalette |
| `Atlas.Core.Forms` / `Atlas.IDE.Forms` (Plugin) | `Text`, `Changes`, `Designer` | Formular-Designer (#402): `IDesignNotification` meldet Änderungen im Designer, nach 500 ms schreibt `TAtlasFormText` das Formular als DFM-Text (`TWriter.OnFindMethodName` liefert die Handlernamen über `IDesigner.GetMethodName`) und schickt ihn per `didOpen`/`didChange` unter dem Namen der .dfm; beim Schließen `didClose`. Server-Änderungen an einem offenen Formular (Umbenennen) prüft `TAtlasFormChanges.Diff`: Erlaubt sind nur geänderte Zeilen `OnX = Handler`; die setzt `TAtlasIdeForms.Apply` im Designer (`CreateMethod`, `SetMethodProp`, `Modified`), nachdem `Atlas.IDE.Editor.WorkspaceEdit` die Units geändert hat. Andere Änderungen an offenen Formularen lehnt Atlas ab, nichts wird geändert |
| `Atlas.Core.Hover` / `Atlas.UI.Hover` / `Atlas.IDE.Hover` (Plugin) | `Contract`, `History`, `Tip`, `Editor` | Hover-Tooltip (#442, #588): Inhalt aus `atlas` der Hover-Antwort (Art, Herkunft, Fundort, Typverweise der Deklaration, Vererbungskette), Verlauf mit höchstens zehn Schritten (Zurück, Sprung im Pfad, derselbe Typ ohne neuen Schritt), Fenster mit Pfadzeile, Kopfzeile (Badge, Art · Herkunft, Fundort), unterstrichenen Typen, Vererbungsabschnitt und Aktionsleiste (Gehe zu, Verwendungen im Ergebnisfenster, Deklaration kopieren, DocWiki); nach dem ersten Klick angeheftet, Esc und Rücktaste/Alt+← über den gemeinsamen Tastatur-Hook; Strg+Klick springt zur Deklaration |
| `Atlas.Core.Diagnostics` / `Atlas.UI.Diagnostics` / `Atlas.IDE.Diagnostics` (Plugin) | `Export`, `ExportDialog` | „Diagnoselog exportieren…“ (#647) im Menü Atlas und in der Befehlspalette: Diagnoselogs des Servers der letzten 7 Tage (ohne Zuordnungsdatei) mit Vorschau genau des ZIP-Inhalts, dann ZIP-Datei an einem gewählten Ort |
| `Atlas.IDE.Editor.Style` (Plugin) | – | Hell/Dunkel nach dem IDE-Thema, ersatzweise nach `AppsUseLightTheme`; Editorschrift; bei jedem Öffnen eines Atlas-Fensters neu abgefragt |
| `Atlas.IDE.Editor.KeyHook` (Plugin) | – | Gemeinsamer Tastatur-Hook des Hauptthreads, nur solange ein Atlas-Fenster Tasten braucht; Clients nach Priorität (Vervollständigung vor Parameter-Hint); keine IDE-Tastaturbindung für Navigationstasten |
| `Atlas.IDE.CodeInsight` (Plugin) | `Manager`, `Composition` | Code Insight-Manager „Atlas IDE Expert“ für Delphi (`IOTACodeInsightManager`): Symbolhinweis (`GetHintText`) und Browse (`GotoDefinition`); startet den Server bei Bedarf neu; Anmeldung beim Laden des Packages |
| `Shell` (Host) | `Shell.Application`, `Shell.Composition`, `Shell.CommandLine`, `Shell.Workspace`, `Shell.Linter`, `Shell.VcsChanges`, `Shell.Diagnostics` | Einstiegspunkt, Kommandozeile, Komposition von Hand, Capabilities; je Arbeitsbereichsordner eigene Konfiguration, eigenes Projekt und eigener Indexaufbau in einen gemeinsamen Symbolindex; Diagnoselog als Beobachter des Dispatchers mit Start- und Endzeile (Grund: clean, inputClosed, parentExited, exception) |

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
- Jede Anfrage sieht der optionale `IJsonRpcRequestObserver` des Dispatchers vor und nach dem Handler im selben Thread, mit Ergebnis, Wartezeit und Laufzeit; darüber schreibt `Shell.Diagnostics` das anonymisierte Diagnoselog (#647). Features melden Grundcodes leerer Ergebnisse über `TRequestDiagnostics`.
- Unerwartete Ausnahmen eines Handlers (nicht `EJsonRpcError`) meldet der Dispatcher über `OnRequestFailed`; die Komposition protokolliert Methode, gekürzte Parameter und Stacktrace. Bei einem Absturz nennt das Log die zuletzt verarbeitete Nachricht.
- Endet die Verbindung (`exit`, Eingabe geschlossen), bricht `Run` offene Anfragen ab und wartet höchstens `WorkTimeout` auf laufende.

Features, die Dateien auswerten, lesen Momentaufnahmen aus `IDocumentStore` (`TServerComposition.Documents`) und abonnieren dessen Ereignisse, um nur die geänderte Datei neu zu verarbeiten. Eine Momentaufnahme ändert sich nie und darf auch in nebenläufigen Anfragen gelesen werden.

Neue LSP-Methoden registrieren ihre Handler in `Shell.Composition` am Dispatcher und tragen ihre Capability in `BuildCapabilities` ein.

## Schichten

Innerhalb von `Atlas.Common` hängen die Features in dieser Richtung voneinander ab (nur nach unten):

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

Datenstrukturen (`Atlas.Common.Index.Contract`):

- `TUnitIndex` je Datei: Unit-Name, Dateiname, Zeitstempel, Inhalts-Hash, uses-Listen aus interface und implementation, Symbole.
- `TIndexSymbol`: Name, Container (umgebender Typ, `''` auf Unit-Ebene), Art (`TIndexSymbolKind`), Bereich der ganzen Deklaration und des Namens, `InInterface`, Vorfahren (Klassen und Interfaces) bzw. Zieltyp (Helfer), deklarierter Typ.
- Sichtbarkeiten, Parameterlisten und Rümpfe stehen nicht im Index. Wer sie braucht (Hover mit published-Properties, Namensauflösung lokaler Variablen), parst die Datei bei Bedarf.

Speicher (`TSymbolIndex`): ein Wörterbuch Dateischlüssel → `TUnitIndex` und eines Unit-Name → Dateischlüssel, beide unter einer `TCriticalSection`. Die Suche nach Namen und Nachfahren läuft linear über alle Symbole; bei den bisherigen Projektgrößen genügt das. `AddUnit` ersetzt den Stand einer Datei vollständig, deshalb sehen Leser nie eine halb aktualisierte Unit.

Aufbau (`TIndexBuilder`, `TIndexService`): ein Hintergrund-Thread liest den Cache, indiziert zuerst die Projektdateien und danach referenzierte Units über den `TUnitFileResolver`. Ein neuer Start bricht den laufenden Aufbau ab und wartet auf ihn. `EnsureUnit` indiziert eine Unit nachträglich im aufrufenden Thread, z. B. für die Namensauflösung.

## Cache-Format

`TIndexCache` schreibt seit #617 ein Binärformat mit String-Tabelle (Formatversion 11; Dateiname weiter `index-*.json`):

```text
'ATLASIDX' Version
Texte:  Anzahl, je Text Bytelänge + UTF-8 (Nummer 0 = '')
Units:  Anzahl, je Unit Kopf (Name, Datei, Zeitstempel, Hash, Merker, uses, Includes mit Zeitstempeln,
        Symbolzahlen) und ein Symbolblock mit Länge
Symbol: Verweise in die Texttabelle, Positionen, Merker, Vorfahren, Typen, Parameter
```

- Zahlen sind Varints (vorzeichenbehaftete per ZigZag); Texte stehen nur einmal in der Tabelle und teilen sich nach dem Laden eine Instanz.
- `ReadEntries` liest nur die Köpfe. Die Symbole einer Unit dekodiert `Expand` erst, wenn der Builder die Unit übernimmt; ein beschädigter Block zählt wie ein fehlender Eintrag.
- Beim Start gilt ein Eintrag, solange Zeitstempel oder Hash zur Datei passen (bei Units mit Includes auch deren Zeitstempel); sonst wird die Datei neu eingelesen.
- Ein Cache mit anderer Version oder fremdem Inhalt (auch die früheren JSON- und Zeilenformate) wird verworfen. Ändert sich `TIndexSymbol`, steigt `FormatVersion`.
- Geschrieben wird nur, wenn etwas neu eingelesen wurde oder Units weggefallen sind.

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
