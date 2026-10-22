# Code-Review: Atlas-IDE-Expert (Branch `main`)

Datum: 21. Oktober 2026 · Stand: Commit `c8f29bc1` („Übergabe: Server-Neustarts durch EStackOverflow (offen)“) · Umfang: 829 Units (Packages + Server), ≈ 362 500 Zeilen Produktivcode, 508 Test-Units mit 5 397 `[Test]`/`[TestCase]` · Delphi 12 / VCL (Plugin) bzw. RTL-Konsole (Server) · Plattformen: Win32 und Win64
Werkzeuge: nur Dateiwerkzeuge (Grep, Read, eigene Skripte für Metriken, Importmatrix, Zyklen und Aufrufgraph). Der Atlas-MCP-Server war in dieser Sitzung nicht erreichbar.
Art: **Delta-Review** gegen `CODE-REVIEW-Atlas-IDE-Expert.md` vom 15.10.2026 (Commit `45c958d`). Dazwischen liegen 477 Commits.

Vorgehen: Zunächst wurden Metriken, Importmatrix und Feature-Zyklen mit denselben Skripten wie am 15.10. neu erhoben, damit die Zahlen vergleichbar sind. Danach wurde jeder der 53 alten Befunde im aktuellen Code nachgeprüft – nicht anhand der Commit-Nachrichten, sondern an der Fundstelle. Der seit dem 15.10. neu hinzugekommene Code (≈ 210 000 Zeilen) wurde nach Größe, Diff-Umfang und den Kategorien des erweiterten Prüfrasters (Korrektheit/Sicherheit, Threads, Ressourcen, Plattform) gezielt gelesen. Die vier wichtigsten neuen Befunde (F-01, F-02, F-05, F-07) wurden zusätzlich direkt am Code gegengeprüft.

Nummerierung: Alte Nummern bleiben stabil. Neue Befunde setzen je Präfix nach der höchsten alten Nummer fort (P-18, S-08, D-11, A-14, K-07). Die im erweiterten Raster neuen Kategorien beginnen bei 01 (F, T, R, X).

---

## 1. Zusammenfassung

In sechs Tagen ist mehr passiert als in manchem Quartal: Der Produktivcode hat sich von ≈ 151 000 auf ≈ 362 000 Zeilen mehr als verdoppelt, die Zahl der Tests von 2 263 auf 5 397. Gleichzeitig wurden 38 der 53 Befunde des letzten Reviews tatsächlich behoben, 13 weitere teilweise. Mehrere Vorschläge wurden weitgehend wie skizziert umgesetzt: `Atlas.Text` als gemeinsamer Textcode mit ADR 0012 und Gleichlauftests, `PinTree` in Referenzsuche und Vervollständigung, `TCompletionRequest` und `TCompletionCollector`, ein Ableitungscache für die Regelengine, `TAtlasEditorSnapshots` statt Pufferlesen im Timer, `TAtlasMainThread` als einziger Weg in den Hauptthread mit eigenem Prüfskript, die Rollenmatrix als Atlas-Regel und im CI. Die beiden kritischen Befunde (A-01 Serverstart im Arbeiterthread, P-01 Extraktion je Token) sind sauber gelöst. Das ist eine bemerkenswerte Leistung.

Der Preis für dieses Tempo ist sichtbar. Vier Dinge stehen heute im Vordergrund:

1. **Der offene Absturz `EStackOverflow` hat drei belegbare Ursachen im Code.** Eine echte Endlosrekursion in `TNameResolver.CurrentClass` bei verschachtelten Typen in `strict`-Abschnitten (F-02), unbegrenzte Baumtiefe bei Operatorketten – das eigene `Rules.Catalog.Data.pas` hat eine Anweisung mit ≈ 1 800 `+` – bei rekursiven Läufern ohne Tiefengrenze (F-03), und eine Fehlerbehandlung in `workspace/diagnostic`, die eine einzelne giftige Datei alle 15 Sekunden erneut rechnet, bis Windows den Prozess beendet (F-04). Welcher Auslöser den konkreten Vorfall verursacht, ist ohne Stack nicht bewiesen; F-04 erklärt aber das Muster im Log vollständig, und eine einzige Zeile Diagnose grenzt die Datei ein.
2. **Die Umsetzung von P-13 hat einen neuen kritischen Fehler erzeugt.** `TSymbolIndex.Units` gibt seit `94bd93df` den gecachten Snapshot ohne Kopie heraus, und die später hinzugekommene uses-Vervollständigung sortiert genau dieses Array an Ort und Stelle (F-01). Danach zeigen die Positionen im Import-Namensindex auf falsche Units, und parallel lesende Threads sehen ein Array, dessen Records gerade vertauscht werden.
3. **Zwei Sicherheitsbefunde im neuen Code.** Der Einstellungsimport lässt die importierte Datei selbst entscheiden, ob sie als Sicherung gilt – mit `"backup": true` setzt eine fremde Datei auch Rechnerwerte wie den Serverpfad, der dann als Programm gestartet wird (F-05). Die Git-Abfrage sucht `git.exe.exe`, findet nie etwas und startet dann `git.exe` aus dem aktuellen Verzeichnis (F-07).
4. **Die Wartungslast hat sich in die Kompositionswurzeln und in parallele Listen verlagert.** `Shell.Composition` ist von 2 687 auf 4 692 Zeilen gewachsen, `Atlas.IDE.CodeInsight.Composition` von 984 auf 4 005; beide sind von der Zyklus- bzw. Rollenprüfung ausgenommen (A-15). Der Zyklus in `Atlas.Core` ist von 5 auf 14 Features gewachsen und für das Prüfskript unsichtbar, weil er nur über Contract-Kanten läuft (A-14). Eine neue Plugin-Einstellung berührt elf Stellen in zwei Units (D-12). Neue Funktionen im Editor führen das in P-04/P-10 behobene Muster – ganzer Puffer im Timer, Einstellungsrecord im Zeichenpfad – wieder ein (P-18).

Hinzu kommt eine Beobachtung zum Prozess: Der Statusblock, der am 16.10. in den alten Bericht eingefügt wurde (Commit `67f64c85`), erklärt alle 53 Befunde für erledigt. Nach Prüfung am Code trifft das auf 38 zu. Das ist kein Vorwurf an die Arbeit – die Teil-Erledigungen sind fast alle sinnvoll –, aber ein „erledigt“ ohne Nachprüfung hat dazu geführt, dass F-01 und A-14 als Nebenwirkung von Erledigungen entstanden und unbemerkt blieben.

**Kernempfehlung:** Zuerst die drei Absturzursachen und F-01 beheben (Vorschlag 5.1, unter einem Tag), dann die beiden Sicherheitsbefunde (5.2, eine Stunde). Danach die Prüfwerkzeuge schließen, die heute an den falschen Stellen blind sind (5.3), und die Einstellungen tabellengesteuert machen, bevor sie weiter linear wachsen (5.4). Die offene Architekturentscheidung A-08 braucht eine Antwort von dir (5.6).

### Befunde nach Schweregrad und Kategorie (offen und teilweise, ohne erledigte)

| Kategorie | Kritisch | Hoch | Mittel | Niedrig | Summe |
|---|:-:|:-:|:-:|:-:|:-:|
| F – Korrektheit/Sicherheit | 2 | 4 | 2 | 1 | 9 |
| P – Performance | – | 1 | 4 | – | 5 |
| T – Threadsicherheit | – | – | 3 | – | 3 |
| R – Ressourcen | – | – | 1 | – | 1 |
| X – Plattform/DPI/Konfiguration | – | – | 1 | 1 | 2 |
| S – Code-Smells | – | – | 4 | 1 | 5 |
| D – Duplikate | – | – | 7 | – | 7 |
| A – Architektur und Tests | – | 2 | 4 | – | 6 |
| K – Dokumentation | – | – | – | 2 | 2 |
| **Summe** | **2** | **7** | **26** | **5** | **40** |

Davon sind 25 neu und 15 Reste alter Befunde (13 teilweise erledigt, 2 offen).

---

## 2. Veränderung seit dem letzten Review

### 2.1 Status der 53 alten Befunde

| Nr | Kurztitel | Status | Beleg (Stand `c8f29bc1`) | Rest |
|---|---|---|---|---|
| P-01 | Referenzsuche extrahiert je Token | erledigt | `Lsp.References.pas:180/240`, `DocumentHighlights.pas:157` pinnen; `Definition.pas:155/190` nutzt `ExtractedUnit` des gepinnten Resolvers; `PinTree` ist schachtelbar (Zähler, `NameResolver.pas:2770`) | – |
| P-02 | Completion rechnet 5–15× je Taste | erledigt | `Handle` pinnt für die ganze Anfrage; `TCompletionRequest` (`CompletionRequest.pas:229`) mit verzögertem `UnitIndex`, `Lines`, `LineBreak` | `Analyze` läuft noch bis zu 6× je Anfrage (→ S-01) |
| P-03 | Regeln bauen Vorbereitungsdaten neu | **teilweise** | `Rules.Derived.pas` (`TRuleDerived`), Engine setzt Cache je Lauf (`Engine.pas:298`), `TSyntaxNode.Walk` (`SyntaxTree.pas:224`) | `Walk` in Rules nur 2× genutzt, 80 handgeschriebene Rekursionen; `Unresolved`, `Deprecated`, `RtlPatterns` bauen je einen eigenen ungepinnten `TNameResolver` (`RtlPatterns.pas:268–276`) – dort kehrt das P-01-Muster zurück |
| P-04 | Timer lesen Puffer 11×/s | erledigt | `Atlas.IDE.Foundation.EditorSnapshot` mit Dirty-Flag, Version, `SafetyMs = 2000`; Timer prüfen `Application.Active` | Neue Funktionen umgehen den Snapshot (→ P-18) |
| P-05 | Lookup = linearer Scan | **teilweise** | `TUnitIndex.PrepareNames`/`SymbolsNamed` (`Index.Contract.pas:391–415`) in `LookupInUnit`, `FindMembers`, `DeclaredMember` | Nur nach Namen, nicht nach Container geschlüsselt; `CollectMembers`, `DefaultProperty`, `OverridableMembers`, `AccessorCandidates`, `MissingInterfaceMembers` scannen weiter |
| P-06 | DFM je Tastendruck parsen | erledigt | `TLspCompletion.FormSnapshot` (`Completion.pas:3454`) | Bei offenem Formular ist der ganze DFM-Text der Cache-Schlüssel |
| P-07 | OverrideItems liest Datei je Kandidat | erledigt | `CachedLines` (`Completion.pas:3161–3170`) | – |
| P-08 | `Result := Result + [X]` mit großem n | erledigt (Hotspots) | References, Highlights, `TreeUnit`, `CodeTokens`, `WithoutKeywords` umgestellt | Das Muster selbst hat sich verdoppelt (Common 473 → 907, Plugin 443 → 1 026); neue Stellen mit großem n in `Shell.Composition.WorkspaceOf` und `CodeLens.ResolveReferences` |
| P-09 | Hover-Tip `Render` 557 Zeilen | erledigt | `Atlas.Core.Hover.Layout` (VCL-frei, Mess-Callback); `Paint` 17 Zeilen, Layout nur bei geändertem `LayoutKey` | Längste Methode wanderte mit: `TBuilder.MemberSection` 161 Zeilen |
| P-10 | InlayHints `PaintLine` | erledigt | `SaveDC`/`RestoreDC`, `FHintFont`, kein `GetPixel`, Boolean-Abfragen `InlayHintsOn` | Muster kehrt in `Pairs.PaintText` zurück (→ P-18) |
| P-11 | Regex-Kompilierung in Schleifen | **teilweise** | `SenderItems` sucht über den Baum (`RoutineAt`), `DfmProperties` und Anonymizer halten Instanzen | 7 statische `TRegEx.Match` je Completion-Anfrage (`Completion.pas:3053, 3138, 3150, 3301, 3317, 4020, 4047`); in Common 64 statische Aufrufe (vorher 51) |
| P-12 | `FindSymbols` Vollscan | erledigt | `IsBuiltinTypeName` in `TypeAt` (`Completion.pas:4226`); `FByName`/`FByAncestor` im `TSymbolIndex` | – |
| P-13 | `Units` kopiert unter Lock | erledigt, **neuer Fehler** | `FUnitsSnapshot` (`SymbolIndex.pas:467–478`), `InternUnit` außerhalb `FLock` | Snapshot wird ohne Kopie geteilt und in `CompletionUses` sortiert (→ **F-01**) |
| P-14 | Long-Poll gegen Watchdog | erledigt | `TimeLimitMs` aus dem Timeout abgeleitet, `TMonitor.Wait/PulseAll` | Neues 20-ms-Polling `Sleep(RunningPollMs)` (`PullDiagnostics.pas:365`) – niedrig |
| P-15 | Popup-Metriken je Aufruf | erledigt | `EnsureMetrics` (`Completion.Popup.pas:149–152, 502`) | – |
| P-16 | MCP blockiert Nachrichtenschleife | **offen, verschlechtert** | `PollMs = 50` | `tools/call` weiter synchron; neues Werkzeug für IDE-Builds wartet bis zu 30 min (`Mcp.IdeBuilds.pas:51`, `Shell.Mcp.pas:287`) |
| P-17 | Helper-Cache geleert | erledigt | Schlüssel aus Unit, Datei, Abschnitt; `ScopeUnits` memoisiert | – |
| S-01 | `Collect` 716 / `Handle` 207 Zeilen | **teilweise** | `TCompletionCollector`, Fall-Listen, `Collect` 143 / `Handle` 95 Zeilen, `ToJson` ausgelagert | Kaskade jetzt in `RegisterCases` (287 Zeilen Closures); 11 Kompatibilitäts-Überladungen mit alten Signaturen; Unit 4 931 Zeilen |
| S-02 | `Composition.Create` 919 Zeilen | **teilweise** | 13 `Wire*`-Methoden, `PickWorkspace`/`Choose`, `SettingsFor` | Unit von 2 687 auf 4 692 Zeilen; `WireCommands` 359 Zeilen; Refactoring-Fachlogik in der Composition; `DefinesFor` weicht vom Fallback ab (→ A-15, T-01) |
| S-03 | `Apply`, `Initialize`, `RegisterFeatures`, Palette | **teilweise** | `Apply` 27 Zeilen (Plan/Execute getrennt), `InitializeParams`, `TAtlasFeatureTable` | `AddFeatures` 450, `RegisterPalette` 385 (vorher 151), `StartCommands` 243 (→ S-09) |
| S-04 | `MemberOrder.Sort` | erledigt | `Sort` 42 Zeilen, fünf benannte Schritte | – |
| S-05 | Einstiegspunkte ohne Guard | erledigt | `TAtlasMainThread.Queue/ForceQueue(AFeature, …)` mit Guard, `Check-MainThreadQueue.ps1`, CLAUDE.md | `Vcs.Worker` nutzt `TThread.Queue(Current, …)` am Helfer vorbei (→ T-02) |
| S-06 | Compile-Thread friert ein | erledigt | äußeres `try/except`, `finally` unter Lock, `NameThreadForDebugging` | – |
| S-07 | Kleinkram | erledigt | Konstanten, `{$WARN … DEFAULT}`, Wächter-Test hinter Diagnose, `TracingTransport.FFailed`, Lecks behoben | – |
| D-01 | Kodierung 4× | erledigt | Plugin leitet an `TTextEncodingProbe` weiter | ANSI-Dekodierung bewusst verschieden (ADR 0012, Punkt 6) |
| D-02 | Anonymisierung 95 % | erledigt | beide Seiten rufen `TTextAnonymizer`; Gleichlauftest `Atlas.Core.Text.Agreement.Tests` | – |
| D-03 | Kleinhelfer vielfach | **teilweise** | Sperrliste in `Check-PackageDependencies.ps1:194–210` | 76× `Split([#10])`, 16× `Pos(#13#10, …)`; Kopien unter anderen Namen nicht gesperrt (→ D-11) |
| D-04 | URI/Position doppelt | **teilweise** | `UriToPath` → `TTextUris`, `TLspTextChanges` → `TLineTable`, Regeln → `TRuleDerived.PositionAt` | 5 neue Positionsrechner (→ D-11) |
| D-05 | Fuzzy-Drift | erledigt | beide Seiten über `TTextFuzzy` | Punktskalen bewusst getrennt |
| D-06 | Zeilendiff 4× | erledigt | alle über `TTextDiff` | zeichenweise Prefix/Suffix-Schleife jetzt 6× (→ D-11) |
| D-07 | UI-Zeichenbausteine | **teilweise** | `Atlas.UI.Popup.Draw` (Thumb, Separator, ToColor); `ProblemColor` mit `AtlasMixFaded = 0.55` | Badge `* 0.62` steht dreimal, neu in `Outline.Breadcrumbs:441` mit 15 statt 17 px; Textblock doppelt |
| D-08 | Dreifache Verdrahtung | erledigt | `Shell.Bootstrap` für ReadSourceText, GroupProjects, globale Einstellungen | Logger bewusst zweimal |
| D-09 | Duplikate in `Lsp.Completion` | **teilweise** | `TCompletionRequest.LineBefore` | `TextLines` (2496), `RangeText` (4161), `OffsetOf` (4176) lokal |
| D-10 | JSONC/Version/Rahmung | erledigt | `TJsoncScanner`, `Atlas.Text.Product.Version`, `MaxContentLength` im Client | – |
| A-01 | Serverstart im Arbeiter | erledigt | `EnsureSession` liefert außerhalb des Hauptthreads nur `RunningSession`; `StopSession` nur im Hauptthread | Restfenster bei Freigabe (→ T-03) |
| A-02 | `Queue(nil, …)` | erledigt | 0 Treffer; `TAtlasMainThread` mit ruhendem Besitzer-Thread und `RemoveQueuedEvents(Owner)` | – |
| A-03 | Reload aus Worker, Namespaces-Race | erledigt | `EInvalidOpException` außerhalb der Schleife, `SlashHost.RunInLoop`, `Lsp.Internals.Namespaces` unter Sperre | Wächter greift nur bei `FLoopThreadId <> 0` |
| A-04 | `FProjectPending` hängt | erledigt | `OnError` setzt zurück und beendet den Fortschritt | – |
| A-05 | `Destroy`-Reihenfolge | erledigt | erst `StopCompiler`/`StopIndexThreads`, dann Diagnoselog; nil-sicher | – |
| A-06 | Watchdog bricht nicht ab | **teilweise** | `Expire` antwortet einmal mit `RequestCancelled`; `CurrentRequest` macht Abbruch in `EnsureUnit` prüfbar | Weiter `TTask.Run` im Default-Pool; nicht kooperierende Handler belegen ihn |
| A-07 | Hover beim Stopp | erledigt | `FHover.Shutdown` in `StopSession` | – |
| A-08 | Host leer, Fachcode im Platform-Package | **offen** | `bce17694` hat nur `Architektur.md:38–44` umdeklariert und vermerkt die ausstehende Antwort | Fachcode jetzt 223 Units, ≈ 101 000 Zeilen (vorher ≈ 58 000) – Entscheidung steht aus (→ 5.6) |
| A-09 | Namensschema, 17er-IDE-Zyklus | **teilweise** | `Atlas.IDE.*` zyklenfrei, 15 `Atlas.IDE.Foundation.*`-Units, Prüfung im Skript | Zyklus nach `Atlas.Core` gewandert, 14 Features (→ A-14) |
| A-10 | Importmatrix, Contract-Klassen | **teilweise** | `TIndexFiles`, `TAtlasUndoNames` umgezogen; `Rules.Contract` ohne `NameResolver` | 18 Treffer, alle als genehmigte Ausnahmen in `atlas.json`, darunter pauschal `CodeInsight.Composition → Atlas.Core.*` (→ A-15) |
| A-11 | `Editing ⇄ Rules` | erledigt | `Editing` importiert `Rules` nicht mehr; Richtung im Skript geprüft | – |
| A-12 | Rollenmatrix ungeprüft | erledigt | Regeln `architecture-role-import`, `architecture-contract-content`; Skript mit `-SelfTest`; CI | Contract-Kanten in der Zyklusprüfung ausgeblendet (→ A-14) |
| A-13 | TimeLimit/FreeOnTerminate | erledigt | `IsCurrent(Generation)` nach `Prepare`, `HangGraceMs` | `FreeOnTerminate` als letzter Ausweg bekannt |
| K-01 | SymbolIndex-Kopf | erledigt | `FByName`/`FByAncestor` existieren jetzt | – |
| K-02 | ADR 0006 vs. Code | erledigt | ADR 0012; 0006 als überholt markiert | ADR 0012 nennt `DUnitX`, `TestResults`, `Checkin`, `Defines` nicht (→ K-08) |
| K-03 | „Im Hauptthread“-Kommentare | erledigt | Kommentare korrigiert, `Assert` in `StopSessionNow` | – |
| K-04 | Verwaiste Summaries | erledigt | `Check-DocComments.ps1` | findet nur Blöcke mit mehreren Summaries |
| K-05 | FormatVersion in Doku | erledigt | ADR und Architektur verweisen auf die Konstante (= 18) | neue Drift in `Core.Welcome.IndexFiles` (→ K-07) |
| K-06 | README Win32/Win64 | erledigt | einheitlich | – |

**Bilanz:** 38 erledigt, 13 teilweise erledigt (P-03, P-05, P-11, S-01, S-02, S-03, D-03, D-04, D-07, D-09, A-06, A-09, A-10), 2 offen (P-16 verschlechtert, A-08 Entscheidung ausstehend), 0 nicht mehr relevant.

### 2.2 Neue Befunde

| Nr | Titel | Schweregrad |
|---|---|---|
| F-01 | Geteilter Unit-Snapshot wird in der uses-Vervollständigung an Ort und Stelle sortiert | Kritisch |
| F-02 | Endlosrekursion `CurrentClass → MethodClass → FindMember → IsVisible → CurrentClass` | Kritisch |
| F-03 | Parser-Tiefengrenze gilt nicht für Operatorketten; rekursive Läufer ohne Grenze | Hoch |
| F-04 | `EStackOverflow` in `workspace/diagnostic`: giftige Datei blockiert jede Runde, Prozess stirbt | Hoch |
| F-05 | Einstellungsimport: `"backup": true` aus der Datei hebt den Rechnerwert-Filter auf | Hoch |
| F-06 | `/inline` ohne Namensauflösung bindet Felder still um | Hoch |
| F-07 | `FindProgram('git.exe')` sucht `git.exe.exe`; Start aus dem aktuellen Verzeichnis | Mittel |
| F-08 | MCP `run_tests`/`build_project` akzeptieren Projekte außerhalb des Arbeitsordners | Mittel |
| F-09 | DUnitX-Filter über 24 000 Zeichen wird still verworfen, alle Tests laufen | Niedrig |
| P-18 | Neue Editorfunktionen lesen den ganzen Puffer im 100–250-ms-Timer; Einstellungsrecord im Zeichenpfad | Hoch |
| T-01 | `NamingFor` liest `FWorkspaces` ohne Sperre aus Completion-Workern | Mittel |
| T-02 | Neue Hintergrunddienste lassen hängende Threads beim Entladen mit `FreeOnTerminate` laufen | Mittel |
| T-03 | Sitzung wird freigegeben, obwohl ein Zeitlimit-Arbeiter noch darin stecken kann | Mittel |
| R-01 | OTA-Notifier nur als rohe Objektzeiger gehalten, ohne `Destroyed` | Mittel |
| X-01 | Keine Bereichs- und Überlaufprüfung in irgendeiner Debug-Konfiguration | Mittel |
| X-02 | Mehrfach-Cursor: feste 2-px-Caret-Breite, DC und Bitmap je Aufruf | Niedrig |
| S-08 | „Meine Issues“ schreibt in jedes Formular, dessen Name „Commit“ enthält | Niedrig |
| S-09 | Plugin-Composition: Feature-Tabelle, daneben handgepflegte Listen für Theme und Einstellungen | Mittel |
| D-11 | Kopien-Sperre prüft nur Namen; neue Positions- und Prefix/Suffix-Rechner unter anderen Namen | Mittel |
| D-12 | Eine neue Plugin-Einstellung berührt 11 Stellen in 2 Units | Mittel |
| D-13 | Gliederungsfenster umgeht den gemeinsamen Dockfenster-Helfer | Mittel |
| A-14 | 14er-Zyklus in `Atlas.Core` läuft über Contract-Kanten, die die Prüfung ausblendet | Hoch |
| A-15 | Kompositionswurzeln mit 4 000+ Zeilen, von Zyklus- und Rollenprüfung ausgenommen | Mittel |
| K-07 | `Core.Welcome.IndexFiles` nennt Cache-Format 16, Konstante ist 18 | Niedrig |
| K-08 | `Atlas.Text` wächst über ADR 0012 hinaus (DUnitX, TestResults, Checkin, Defines) | Niedrig |

### 2.3 Metrik-Trend

| Kennzahl | 15.10. (`45c958d`) | 21.10. (`c8f29bc1`) | Veränderung |
|---|--:|--:|---|
| Units (Packages + Server) | 428 | 829 | × 1,9 |
| Zeilen Produktivcode | ≈ 151 000 | ≈ 362 500 | × 2,4 |
| davon `Atlas.Common` | 83 235 | 133 776 | + 61 % |
| davon `Atlas.IDE.Expert` | 58 874 | 213 284 | × 3,6 |
| davon `Atlas.Text` | – | 3 739 | neu |
| davon Server-Shell | 6 277 | 10 391 | + 66 % |
| Units > 1 500 Zeilen | 6 | 20 (+ `Shell.Composition`) | × 3,5 |
| Methoden > 60 Zeilen | 262 | 650 | × 2,5 (je 1 000 Zeilen: 1,7 → 1,8) |
| Längste Methode | 919 (`TServerComposition.Create`) | 706 (`TInlineRefactoring.InlineMethod`) | – |
| Größte Unit | 4 307 (`Lsp.Completion`) | 5 418 (`UI.Settings.Page`) | – |
| Test-Units / Tests | 254 / 2 263 | 508 / 5 397 | × 2,0 / × 2,4 |
| Tests für die Server-Shell | 3 Units | 10 Units | besser, aber dünn für 10 391 Zeilen |
| Interne Imports | 2 003 | 4 686 | × 2,3 |
| Importmatrix-Verstöße | 15 | 18 (alle als Ausnahme genehmigt) | – |
| Feature-Zyklen | 3 (2 + 5 + 17 Features) | 1 (14 Features in `Atlas.Core`) | strukturell besser, Rest gewachsen |
| `TThread.Queue(nil, …)` im Plugin | 31 | 0 | erledigt |
| `Result := Result + [`-Muster | 399 / 243 | 907 / 1 026 | verdoppelt |
| `Sleep(`-Stellen | 8 | 13 | + 5 |
| Polling-Timer im IDE-Layer | – | ≈ 29, viele 100–250 ms | neu gemessen |
| `/// <summary>`-Dichte (je Methode, Plugin) | 0,57 | 0,68 | besser |

Die Zahl langer Methoden pro 1 000 Zeilen ist nahezu konstant geblieben – das Wachstum ist also nicht schlampiger, sondern einfach groß. Die Testdichte (Tests je 1 000 Zeilen) ist von 15 auf 14,9 praktisch gleich geblieben, was bei diesem Tempo bemerkenswert ist.

### 2.4 Fahrplan-Einhaltung

Der Fahrplan vom 15.10. wurde in der Reihenfolge „sofort – nächstes Release – langfristig“ fast vollständig in sechs Tagen abgearbeitet; nur 4.5 (Fachcode in den Host) ist nicht begonnen und als Entscheidungsfrage offen. Die Umsetzung folgte meist der Skizze, bei 4.3 (`Atlas.Text`) wurde die dokumentierte Alternative (a) gewählt – Quelltext in beide Packages statt eigenem BPL –, was gut begründet ist.

Was gefehlt hat, ist der Kontrollschritt nach jeder Erledigung: In mindestens drei Fällen hat die Lösung das Problem verschoben statt beseitigt (P-13 → F-01, A-09 → A-14, S-02/S-03 → A-15), und das Prüfskript wurde an genau den Stellen um Ausnahmen erweitert, an denen sich die Probleme jetzt sammeln. Der Statusblock „Alle Befunde sind erledigt“ im alten Bericht sollte durch diesen Bericht ersetzt bzw. korrigiert werden.

---

## 3. Projektübersicht und Metriken

### 3.1 Ausgabeartefakte

| Ausgabeartefakt | Art | Units | Zeilen | Methoden | Ø uses je Unit | Methoden > 60 Z. | `/// <summary>` | Tests (Units) |
|---|---|--:|--:|--:|--:|--:|--:|--:|
| `Atlas.Text` | Quelltext, in beide Packages eingebunden (ADR 0012) | 14 | 3 739 | 130 | 1,1 | 5 | 135 | 13 |
| `Atlas.Common` | Runtime-Package, nur RTL | 321 | 133 776 | 5 438 | 8,2 | 309 | 4 007 | 276 |
| `Atlas.Windows` | Runtime-Package, RTL + Winapi | 12 | 1 350 | 62 | 3,3 | 2 | 31 | 6 |
| `Atlas.IDE.Expert` | Design-Time-Package (VCL, OTA), `{$LIBSUFFIX AUTO}` | 456 | 213 284 | 9 699 | 10,6 | 319 | 6 601 | 184 |
| `AtlasServer` (Shell) | Konsolenanwendung | 13 | 10 391 | 304 | – | 15 | – | 10 |
| `AtlasSetup` | VCL-Anwendung | – | 2 392 | – | – | – | – | 2 |

### 3.2 Die größten Units

| Unit | Zeilen | Methoden | uses (intf/impl) | Längste Methode | Zeilen |
|---|--:|--:|:-:|---|--:|
| `Atlas.UI.Settings.Page` | 5 418 | 159 | 32/20 | `Create` | 564 |
| `Atlas.Common.Lsp.Completion` | 4 932 | 121 | 17/47 | `RegisterCases` | 287 |
| `Shell.Composition` | 4 692 | 114 | 88/74 | `WireCommands` | 359 |
| `Atlas.IDE.CodeInsight.Composition` | 4 005 | 257 | 0/191 | `AddFeatures` | 450 |
| `Atlas.Core.Settings.PluginSchemaData` | 3 701 | 1 | – | generiert | – |
| `Atlas.UI.Strings` | 3 406 | 9 | 1/1 | – | – |
| `Atlas.Common.Semantics.NameResolver` | 3 360 | 120 | 6/7 | `ExprSymbol` | 122 |
| `Atlas.Common.Pascal.Parser` | 2 546 | 208 | 3/4 | `ParseTypeBody` | 183 |
| `Atlas.Core.Settings.Plugin` | 2 449 | 19 | 2/8 | `Load` | 402 |
| `Atlas.Common.Configuration.Parser` | 2 141 | 93 | 2/6 | `TValidator.Run` | 215 |
| `Atlas.UI.UnitSearch.Window` | 2 021 | 78 | 16/9 | – | 129 |
| `Atlas.Core.Projects.Summary` | 2 002 | 70 | 2/5 | – | 139 |
| `Atlas.UI.Completion.Popup` | 1 911 | 89 | 21/5 | – | 115 |
| `Atlas.Core.Lsp.Session` | 1 851 | 95 | 12/2 | – | 79 |
| `Atlas.IDE.CodeInsight.Manager` | 1 837 | 91 | 19/26 | – | 90 |
| `Atlas.Common.Editing.Inlining` | 1 707 | 46 | 5/8 | `InlineMethod` | 706 |
| `Atlas.IDE.Completion.Editor` | 1 699 | 79 | 17/35 | – | 170 |
| `Atlas.Common.Lsp.ChangeSignature` | 1 643 | 64 | 10/13 | `Execute` | 306 |

### 3.3 Top-10-Methoden nach Länge

| Zeilen | Methode | Bemerkung |
|--:|---|---|
| 706 | `Atlas.Common.Editing.Inlining.TInlineRefactoring.InlineMethod` | neu; F-06 |
| 564 | `Atlas.UI.Settings.Page.TAtlasSettingsPage.Create` | wächst je Einstellung (D-12) |
| 480 | `Atlas.Text.DUnitX.TDUnitXSource.Scan` | neu; K-08 |
| 450 | `Atlas.IDE.CodeInsight.Composition.AddFeatures` | S-03-Rest, S-09 |
| 423 | `Atlas.UI.Settings.Page.TAtlasSettingsPage.SaveTo` | D-12 |
| 405 | `Atlas.IDE.Commands.Bindings.TAtlasIdeEditorKeys.Rebind` | D-12 (Tasten) |
| 402 | `Atlas.Core.Settings.Plugin.TAtlasPluginSettings.Load` | D-12 |
| 400 | `Atlas.Core.Settings.Plugin.TAtlasPluginSettings.Defaults` | D-12 |
| 385 | `Atlas.IDE.CodeInsight.Composition.RegisterPalette` | S-09 |
| 383 | `Atlas.UI.Settings.Page.TAtlasSettingsPage.LoadControls` | D-12 |

Sieben der zehn längsten Methoden sind lineare Listen – Einstellungen, Tastenbelegungen, Feature-Registrierungen. Sie sind lang, aber nicht komplex; das Risiko liegt in der Pflege paralleler Listen (D-12, S-09), nicht in der Logik.

### 3.4 Fan-in (meistgenutzte Units)

| Fan-in | Unit |
|--:|---|
| 186 | `Atlas.Common.Documents.Contract` |
| 155 | `Atlas.UI.Strings` |
| 139 | `Atlas.Core.Diagnostics.Guard` |
| 122 | `Atlas.Common.Pascal.Contract` |
| 114 | `Atlas.Common.Pascal.SyntaxTree` |
| 103 | `Atlas.Common.Index.Contract` |
| 97 | `Atlas.Text.Lines` |
| 91 | `Atlas.Common.Configuration.Contract` |
| 84 | `Atlas.IDE.Foundation.Settings` |
| 72 | `Atlas.Core.Settings.Plugin` |
| 66 | `Atlas.Core.Diagnostics.MainThread` |
| 61 | `Atlas.Common.Rules.Contract` |

Das ist ein gesundes Bild: Die meistgenutzten Units sind Contracts und Basisdienste. `Atlas.Core.Settings.Plugin` mit Fan-in 72 ist die Ausnahme – eine konkrete Klasse mit ≈ 340 Feldern, die von 72 Units direkt gelesen wird (P-18).

### 3.5 Abhängigkeiten

```text
Ausgabeartefakte (unverändert bis auf Atlas.Text):
  AtlasServer (Shell) ──► Atlas.Windows ──► Atlas.Common ──► Atlas.Text ──► RTL
  Atlas.IDE.Expert ──► RTL, VCL, vclwinx, designide       (Atlas.Text per 'contains' einkompiliert)

Atlas.Common: azyklisch (Editing ⇄ Rules aufgelöst)

Plugin-Schichten:
  Atlas.IDE.*  (34 Features, inkl. Foundation)  azyklisch
  Atlas.UI.*                                     azyklisch
  Atlas.Core.* ── ein Zyklus über 14 Features:
     Ci, Completion, Diagnostics, Editor, Files, Generate, Hover,
     Lsp, Outline, Problems, Projects, Results, Settings, Undo
     – geschlossen nur über vier Contract-Kanten (A-14):
       Editor.GutterColumn → Problems.Contract
       Lsp.Session         → Projects.Contract
       Lsp.Session         → Hover.Contract
       Settings.Plugin     → Generate.Contract
```

### 3.6 Projektkonfiguration

| Projekt | Debug: `$R`/`$Q` | Optimierung Debug | Debug-Info Release | Plattformen |
|---|---|---|---|---|
| `Atlas.Text`, `Atlas.Common`, `Atlas.Windows` | nicht gesetzt (aus) | aus | 1 | Win32, Win64 |
| `Atlas.IDE.Expert` | nicht gesetzt (aus) | aus | 0 | Win32, Win64 (`LIBSUFFIX AUTO`) |
| `AtlasServer` | nicht gesetzt (aus) | aus | 1 | Win32, Win64 |
| `AtlasSetup` | nicht gesetzt (aus) | aus | 1 | Win32 |
| `Atlas.Tests` | nicht gesetzt (aus) | aus | 0 | Win32, Win64 |

Keine eingecheckten `.dcu`, `.local`, `.identcache` oder `__history`. Map-Dateien werden für Stacktraces erzeugt (gut). Kein Projekt setzt `{$MAXSTACKSIZE}`; es gilt die Vorgabe von 1 MB je Thread (relevant für F-03). Bereichs- und Überlaufprüfung siehe X-01.

---

## 4. Befunde

Erledigte alte Befunde werden hier nicht wiederholt (siehe 2.1). Teilweise erledigte alte Befunde stehen mit ihrer alten Nummer und nur dem Rest; neue Befunde vollständig. Innerhalb jeder Kategorie nach Schweregrad sortiert.

### 4.1 Korrektheit und Robustheit (F) – inkl. Sicherheit

Die drei Befunde F-02, F-03 und F-04 hängen zusammen: Sie sind die belegbaren Ursachen des in `docs/Uebergabe.md` (Commit `c8f29bc1`) als offen gemeldeten Absturzes „Server-Neustarts durch EStackOverflow“. F-04 erklärt das Muster im Log (alle ≈ 15 s ein Überlauf, nach einigen davon endet der Prozess ohne Endzeile); F-02 und F-03 sind die Kandidaten für den Überlauf selbst.

#### F-01 · Geteilter Unit-Snapshot wird in der uses-Vervollständigung an Ort und Stelle sortiert · Schweregrad: Kritisch · Aufwand: S
**Fundstelle:** `Atlas.Common.Index.SymbolIndex.pas`, Zeile 467–478, `TSymbolIndex.Units`; `Atlas.Common.Lsp.CompletionUses.pas`, Zeile 467–472; Mitbenutzer `Atlas.Common.Index.NameIndex.pas` (Felder `Units`, `UnitPos`/`SymbolPos`, Zeile 31–40) und `Atlas.Common.Lsp.CompletionCollector.pas`, Zeile 936.
**Beobachtung:**
```pascal
function TSymbolIndex.Units: TArray<TUnitIndex>;
begin
  FLock.Enter;
  try
    // Schnappschuss bis zur nächsten Änderung (Code-Review P-13); dynamische Arrays sind referenzgezählt.
    if FUnitsSnapshot = nil then
      FUnitsSnapshot := FFiles.Values.ToArray;
    Result := FUnitsSnapshot;
```
```pascal
Units := ARequest.Index.Units;                        // CompletionUses.pas:467
TArray.Sort<TUnitIndex>(Units, TComparer<TUnitIndex>.Construct(
  function(const ALeft, ARight: TUnitIndex): Integer
  begin
    Result := CompareText(ALeft.UnitName, ARight.UnitName);
  end));
```
**Warum das ein Problem ist:** Der Kommentar in `Units` setzt voraus, dass Referenzzählung vor Änderungen schützt. Das gilt für Strings (Copy-on-Write), nicht für dynamische Arrays: Alle Aufrufer teilen denselben Speicherblock, und `TArray.Sort` vertauscht die Elemente in diesem Block. Folgen: (1) `TImportNameIndex` hält dasselbe Array und Positionen (`UnitPos`, `SymbolPos`) hinein; nach jeder uses-Vervollständigung (Standard `UsesDetails = True`) liefern `Names.Units[Entry.UnitPos].Symbols[Entry.SymbolPos]` Symbole aus falschen Units – falsche Auto-Import-Vorschläge, ohne Bereichsprüfung (X-01) auch Zugriffe hinter dem Array-Ende. (2) Während des Sortierens lesen nebenläufige Anfragen (Completion, SemanticTokens, Regeln) dasselbe Array; das Vertauschen von Records mit zehn verwalteten Feldern ist nicht atomar und kann Referenzzähler beschädigen. Entstanden ist der Fehler aus dem Zusammentreffen zweier korrekter Einzeländerungen (`94bd93df` P-13, `8f6394c1` #469).
**Empfehlung:** In `Units` `Result := Copy(FUnitsSnapshot)` zurückgeben (eine Kopie der Referenzen, die Records selbst werden nicht tief kopiert) **oder** den Vertrag „nur lesen“ im Interface dokumentieren und in `CompletionUses` auf `Copy(ARequest.Index.Units)` sortieren. Ersteres ist sicherer, weil es künftige Aufrufer schützt; die Kosten sind eine Array-Allokation je Aufruf statt je Änderung – immer noch weit unter dem Stand vor P-13. Test: zweimal `Units` holen, das erste sortieren, das zweite auf unveränderte Reihenfolge prüfen.
**Konfidenz:** hoch (am Code bestätigt).

#### F-02 · Endlosrekursion `CurrentClass → MethodClass → FindMember → IsVisible → CurrentClass` · Schweregrad: Kritisch · Aufwand: S
**Fundstelle:** `Atlas.Common.Semantics.NameResolver.pas`, `CurrentClass` Zeile 1217–1229, `IsVisible` Zeile 1248–1270, `FindMembers` Zeile 1330–1386 (Aufruf von `IsVisible` Zeile 1370), `MethodClasses` Zeile 1679–1711.
**Beobachtung:**
```pascal
function TNameResolver.CurrentClass(out AType: TResolvedSymbol): Boolean;
begin
  // Einmal je Prepare: Klasse der umgebenden Methode.
  if FClassState = 0 then
  begin
    if (FTree <> nil) and MethodClass(FClass) then   // FClassState bleibt während des Aufrufs 0
      FClassState := 2
    else
      FClassState := 1;
  end;
```
```pascal
    TIndexVisibility.StrictPrivate:
      Result := SameUnit and CurrentClass(Own) and SameText(Own.QualifiedName, AOwner.QualifiedName);
```
**Warum das ein Problem ist:** `MethodClasses` löst bei `procedure TAussen.TInnen.X` den Typ `TInnen` mit `FindMember(Current, 'TInnen', …)` auf. `FindMembers` prüft die Sichtbarkeit über `IsVisible`. Ist `TInnen` im `strict private`- oder `strict protected`-Abschnitt von `TAussen` deklariert, ruft `IsVisible` wieder `CurrentClass` auf – mit `FClassState = 0`, also erneut `MethodClass`. Die Rekursion endet erst am Stapelende. Betroffen ist jede Namensauflösung in einer solchen Methode: Hover, Definition, Vervollständigung und alle Regeln mit Resolver. Die am 21.10. neu eingeführte Regel `deprecated-symbol` (`73ed957a`, `Rules.Builtin.Deprecated.pas:158`) ruft `Resolve` in jeder Datei der Workspace-Diagnose – an dem Tag, an dem die Abstürze begannen. Verschachtelte Typen in `strict`-Abschnitten sind in Anwendercode üblich; im Atlas-Repo selbst gibt es keinen (alle 44 Dateien mit `TA.TB.X`-Implementierungen per Skript geprüft), deshalb ist F-02 als Auslöser des konkreten Vorfalls unwahrscheinlich, als Absturzursache bei Anwendern aber sicher.
**Empfehlung:** Wiedereintritt sperren – `FClassState := 1` vor dem Aufruf von `MethodClass` setzen, bei Erfolg auf 2:
```pascal
  if FClassState = 0 then
  begin
    FClassState := 1;                       // während der Suche: keine umgebende Klasse
    if (FTree <> nil) and MethodClass(FClass) then
      FClassState := 2;
  end;
```
Alternativ in `MethodClasses` verschachtelte Typen ohne Sichtbarkeitsprüfung suchen (sie sind von der eigenen Methode aus immer sichtbar). Test: `TA = class strict private type TB = class procedure X; end; end;` und `Resolve` im Rumpf von `TA.TB.X`.
**Konfidenz:** hoch für den Fehler (am Code bestätigt); Annahme, ob er den konkreten Vorfall auslöst.

#### F-03 · Parser-Tiefengrenze gilt nicht für Operatorketten; rekursive Baumläufer ohne Grenze · Schweregrad: Hoch · Aufwand: M
**Fundstelle:** `Atlas.Common.Pascal.Parser.pas`, `Binary` Zeile 2115–2122, `ParseSimpleExpression` Zeile 2153–2168, `ParseFactor` Zeile 2206–2215; `Atlas.Common.Pascal.SyntaxTree.pas`, `TSyntaxNode.Walk` Zeile 224–232; rekursive Läufer u. a. in `Rules.Builtin.Unused` (`ContainsKind`, `CollectUses`), `Rules.Builtin.Flow.ContainsKind`, `Rules.Builtin.Capture.CollectIdentifiers`, `Rules.Builtin.FreeFields.ScanCreations` (neu 21.10.), `Rules.Builtin.Deprecated.HeaderNameOffsets` (neu, Zeile 79), rekursiver Destruktor von `TSyntaxNode`.
**Beobachtung:**
```pascal
  Result := ParseTerm;
  while (... InWords(Current.Text, AdditiveSymbols)) or IsKw(['or', 'xor']) do
  begin
    ...
    Result := Binary(Op, Result, ParseTerm, Start);   // linkslastig, kein EnterNesting
  end;
```
```pascal
procedure TSyntaxNode.Walk(const AVisit: TSyntaxNodeVisit);
  ...
  for Index := 0 to ChildCount - 1 do
    Children[Index].Walk(AVisit);
```
**Warum das ein Problem ist:** `EnterNesting`/`TooDeep` (Grenze 256) zählt nur geschachtelte Faktoren. Eine Kette `A + B + C + …` baut einen linkslastigen Baum, dessen Tiefe der Zahl der Operatoren entspricht, ohne dass die Grenze greift. Im eigenen Projekt enthält `Atlas.Common.Rules.Catalog.Data.pas` (Teil von `Atlas.Common.dpk`, also in jeder Workspace-Diagnose des Atlas-Repos) eine Anweisung mit ≈ 1 800 `+` – am 15.10. waren es ≈ 1 500; die Datei wächst mit jeder Regel. Jeder rekursive Läufer geht diese Tiefe vollständig hinab; mit Rahmen von einigen hundert Bytes im Debug-Build und 1 MB Stack je Pool-Thread (kein `{$MAXSTACKSIZE}`) ist die Reserve knapp, und sie schrumpft mit jeder neuen Regel und jedem neuen Läufer. Das ist der wahrscheinlichste Auslöser des konkreten Vorfalls im Atlas-Repo.
**Empfehlung:** (1) Ketten gleicher Priorität als n-äre Knoten speichern (`TSyntaxNodeKind.BinaryChain` mit Operandenliste) – das beseitigt die Tiefe an der Quelle und ändert nur Konsumenten, die `Binary` mit genau zwei Kindern erwarten. Kurzfristig `TooDeep` auch in den Binär-Schleifen zählen. (2) `Walk` und die rekursiven Hilfsläufer iterativ mit `TStack<TSyntaxNode>` schreiben, wie es `Atlas.Common.Semantics.Recursion` (`CollectRoutines` Zeile 337–361) bereits vormacht; den Destruktor ebenso (der Parser „gibt Bäume iterativ frei“ laut Architektur – prüfen, ob das für alle Freigabepfade gilt). (3) Test mit 10 000 Summanden, der jede Builtin-Regel einmal über den Baum laufen lässt.
**Konfidenz:** hoch für die unbegrenzte Tiefe; mittel als Ursache des Vorfalls.

#### F-04 · `EStackOverflow` in `workspace/diagnostic`: eine giftige Datei blockiert jede Runde, nach einigen Überläufen stirbt der Prozess · Schweregrad: Hoch · Aufwand: S
**Fundstelle:** `Atlas.Common.Lsp.PullDiagnostics.pas`, `CollectWorkspace` Zeile 487–540 (Zeile 525); `Atlas.Common.JsonRpc.Dispatcher.pas`, Zeile 526–535.
**Beobachtung:**
```pascal
      Items := CachedDiagnose(Uri, ResultId, Disk, ACancellation);
      ...
  except
    Result.Free;
    raise;          // ganze Runde verworfen, APrevious nicht zurückgegeben
```
```pascal
      on E: Exception do
      begin
        ...
        Result := ErrorResponse(AId, E);
```
**Warum das ein Problem ist:** Die Dateiliste läuft immer in derselben Reihenfolge. Die erste Datei mit Überlauf bricht jede Runde ab, alle Dateien danach werden nie geprüft, und weil der Fehler nicht im Cache gemerkt wird, rechnet der nächste Long-Poll dieselbe Datei erneut – genau das Bild „error:EStackOverflow alle ≈ 15 s“. `EStackOverflow` wird wie jede andere Ausnahme gefangen; unter Win64 stellt Delphi die Schutzseite (Guard Page) des Thread-Stacks nach einem Überlauf aber nicht wieder her. Trifft der nächste Überlauf denselben Pool-Thread, beendet Windows den Prozess ohne weitere Ausnahme – das ist das gemeldete „endet nach einigen davon, ohne Endzeile“. Ohne die URI im Diagnoselog bleibt zudem offen, welche Datei es ist.
**Empfehlung:** Sofort zur Eingrenzung: vor `CachedDiagnose` `TRequestDiagnostics.Note('file', Uri)` – dann nennt das Diagnoselog die Datei, ohne Debugger. Dauerhaft: Fehler je Datei fangen, als leeren Bericht mit `resultId` und Fehlerzustand merken und mit der nächsten Datei weitermachen; `EStackOverflow` gesondert behandeln – Datei auf eine Sperrliste für diese Dokumentversion setzen und den betroffenen Pool-Thread nicht weiterverwenden (eigener Pool mit Austausch oder kontrollierter Neustart des Servers mit Meldung an den Client statt stillem Tod).
**Konfidenz:** hoch.

#### F-05 · Einstellungsimport: `"backup": true` aus der importierten Datei hebt den Filter für Rechnerwerte auf · Schweregrad: Hoch · Aufwand: S
**Fundstelle:** `Packages/Atlas.IDE.Expert/Source/Core/Settings/Atlas.Core.Settings.Transfer.pas`, Zeile 972 (Datei lesen) und 1102–1103 (`Preview`); `Atlas.Core.Settings.Catalog.pas`, Zeile 252–255 (`Transferable`); Verwendung: `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.pas`, Zeile 510–511 (`ServerPath`), `IDE/Welcome/Atlas.IDE.Welcome.QuickActions.pas`, Zeile 799–803 (`OpenConsole`).
**Beobachtung:**
```pascal
Result.Backup := IsTrue(Root.GetValue('backup'));          // 972: Wert aus der importierten Datei
...
if not Entry.Transferable and not AFile.Backup then         // 1102
  Item.Status := isSkipped
// Catalog 254:
Result := not State and not Machine;
```
**Warum das ein Problem ist:** Ob eine Datei als eigene Sicherung gilt – und damit auch rechnergebundene Werte (`x-machine`) zurückschreiben darf –, entscheidet allein ein Feld in der Datei selbst. Eine weitergegebene `atlas-settings.json` mit `"backup": true` kann so `server.path` setzen; den liest `Manager.ServerPath` und startet ihn beim nächsten Serverstart als Sprachserver. `welcomePage.quickActions.console` ist gar nicht als `x-machine` markiert und lässt sich mit jedem normalen Import setzen; ein Klick auf „Konsole“ führt den Wert per `ShellExecute` aus. Die Vorschau zeigt die Änderung zwar an, aber ein harmlos benannter „Team-Einstellungen“-Import ist genau der Fall, in dem niemand jede Zeile liest. Ergebnis: Programmausführung über eine Einstellungsdatei.
**Empfehlung:** Ob eine Datei eine Sicherung ist, nur aus Ort und Namen ableiten (`BackupFolder` + `BackupPrefix`), nie aus dem Inhalt. `welcomePage.quickActions.console` und `welcomePage.help.reportFolder` als `x-machine` markieren. In der Vorschau Schlüssel, die Programme oder Pfade starten, als eigene Warnstufe zeigen und standardmäßig abwählen. Test: Import einer Datei mit `"backup": true` außerhalb des Sicherungsordners darf keinen `x-machine`-Wert übernehmen.
**Konfidenz:** hoch (Kette vollständig gelesen, am Code bestätigt).

#### F-06 · Slash-Befehl `/inline` bettet ohne Namensauflösung ein und bindet Felder still um · Schweregrad: Hoch · Aufwand: M
**Fundstelle:** `Atlas.Common.Editing.RefactoringCommands.pas`, Zeile 129–140; `Atlas.Common.Editing.Inlining.pas`, `InlineMethod` Zeile 1369–1370, `CollectRoutines` Zeile 853–869. Gegenstück korrekt: `Atlas.Common.Lsp.Refactorings` (`InlineActions`, Zeile 515–558).
**Beobachtung:**
```pascal
    Options := TInlineOptions.Default;            // Lookup = nil
    Options.Style := AContext.Style;
    ...
        Routines := TInlineRefactoring.FindRoutines(Source.Tree, Call.Name);
        if Length(Routines) = 1 then
          Found := TInlineRefactoring.InlineMethod(Inline_, Token.StartPos, Inline_, Routines[0], ...
```
```pascal
      if not Assigned(AOptions.Lookup) then
        Continue;          // vor der Empfänger-Qualifizierung und vor „bedeutet am Aufruf etwas anderes“
```
**Warum das ein Problem ist:** `CollectRoutines` vergleicht nur den Kurznamen. `SL.Add('x')` wird durch den Rumpf von `TMyList.Add` aus derselben Datei ersetzt, wenn es dort genau einen Rumpf `Add` gibt – obwohl `SL` eine `TStringList` ist. Ohne `Lookup` erhalten Mitglieder keinen Empfänger: Aus `Other.Inc` mit dem Rumpf `Inc(FCount)` wird `Inc(FCount)`, das jetzt das Feld des **Aufrufers** erhöht. Der entstehende Code übersetzt fehlerfrei und tut etwas anderes. Auch die Prüfungen auf Sichtbarkeit und Schattierung entfallen. Ein Refactoring, das still falschen, kompilierbaren Code erzeugt, ist schlimmer als eines, das ablehnt.
**Empfehlung:** In `InlineMethod` ohne `Lookup` abbrechen („keine Namensauflösung verfügbar“), oder den Slash-Host mit `InlineLookup(Resolver)` versorgen und das Ziel wie im LSP-Weg auflösen. Test: zwei Klassen mit gleichnamiger Methode in einer Unit, `/inline` auf dem Aufruf der anderen Klasse muss ablehnen.
**Konfidenz:** hoch.

#### F-07 · `FindProgram('git.exe')` sucht `git.exe.exe`; danach Start von `git.exe` aus dem aktuellen Verzeichnis · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Application/Source/Shell/Shell.Composition.pas`, Zeile 2795 (`GitStateOf`); `Application/Source/Shell/Shell.VcsChanges.pas`, Zeile 111–120 (`FindProgram`); `Atlas.Windows.Compiler.Adapters.ProcessRunner.pas`, Zeile 187.
**Beobachtung:**
```pascal
  Request.Executable := TVcsChanges.FindProgram('git.exe');      // Shell.Composition:2795
...
  for Dir in GetEnvironmentVariable('PATH').Split([PathSep]) do
    if (Dir <> '') and TFile.Exists(TPath.Combine(Dir.Trim(['"']), AName + '.exe')) then
      Exit(TPath.Combine(Dir.Trim(['"']), AName + '.exe'));
  Result := AName;
```
**Warum das ein Problem ist:** Die PATH-Suche findet nie etwas, weil sie `git.exe.exe` sucht. Danach ist `lpApplicationName` von `CreateProcess` ein nackter Name; `CreateProcess` sucht diesen dann nur im aktuellen Verzeichnis, nicht im PATH (das sagt der Kommentar in `FindProgram` selbst). Folge 1: Der Git-Zustand in der Unit-Suche ist praktisch immer leer – ein stiller Funktionsfehler. Folge 2: Liegt im aktuellen Verzeichnis des Servers (typischerweise der Projektordner) eine `git.exe`, wird sie ausgeführt (Binary Planting). Die übrigen Git-/SVN-Aufrufe in `Shell.VcsChanges` übergeben den Namen ohne Endung und sind korrekt.
**Empfehlung:** `FindProgram('git')`; `FindProgram` liefert bei leerem Ergebnis `''` statt des nackten Namens, und der Aufrufer startet dann nicht. Test für `FindProgram` mit und ohne Endung.
**Konfidenz:** hoch (am Code bestätigt).

#### F-08 · MCP `run_tests` und `build_project` akzeptieren Projekte außerhalb des Arbeitsordners und starten deren Ausgabe · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Application/Source/Shell/Shell.Mcp.pas`, Zeile 536–558 (`run_tests`), gleiches Muster Zeile 280 (`build_project`); Einschränkung im Modus `restricted`: `Atlas.Common.Mcp.Server.pas`, Zeile 170.
**Beobachtung:**
```pascal
      if (Wanted <> '') and (...) and not TPath.IsPathRooted(Wanted) then
        Wanted := TPath.GetFullPath(TPath.Combine(ARoot, Wanted));
      if (Wanted <> '') and TPath.IsPathRooted(Wanted) and FileExists(Wanted) then
        Target.Project := Wanted
      ...
      Target.Executable := TMcpTestTools.ExecutableOf(Info);
```
**Warum das ein Problem ist:** Ein absoluter Pfad oder `..\..\x.dproj` wird ohne Prüfung gegen `ARoot` übernommen, danach wird die Ausgabe-EXE gestartet, deren Pfad in dieser Projektdatei steht. Ein MCP-Client, dessen Modell per Prompt-Injection gesteuert wird (z. B. über einen präparierten Kommentar im Quelltext), kann so jedes Programm starten, auf das irgendeine erreichbare `.dproj` zeigt. Der Modus `restricted` sperrt Prozess-Werkzeuge, im Normalmodus gibt es keine Grenze.
**Empfehlung:** Projekt und EXE müssen nach `GetFullPath` unter `ARoot` liegen (Präfixvergleich ohne Groß-/Kleinschreibung, mit abschließendem Trenner); sonst Ablehnung mit Meldung. Dieselbe Prüfung als Hilfsfunktion `TMcpPaths.InsideRoot` für alle schreibenden und startenden Werkzeuge.
**Konfidenz:** hoch für das Verhalten; mittel für den Schweregrad, der vom Einsatzmodus abhängt.

#### F-09 · DUnitX-Filter über 24 000 Zeichen wird still verworfen; dann laufen alle Tests · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Atlas.Text.DUnitX.pas`, `TDUnitXCommandLine.Arguments`, Zeile 1063–1081.
**Beobachtung:**
```pascal
  if (Run <> '') and (Length(Run) <= MaxRunLength) then
    Result := Result + ['--run:' + Run];
```
**Warum das ein Problem ist:** Bei vielen ausgewählten Tests startet die volle Suite (bis zu 3 600 s Zeitlimit), während der Bericht die gewünschte Teilliste erwartet.
**Empfehlung:** Nach Fixture zusammenfassen oder in mehrere Läufe aufteilen; wenn beides nicht geht, mit Meldung ablehnen, nie still auf „alle“ umschalten.
**Konfidenz:** hoch.

### 4.2 Performance (P)

#### P-18 · Neue Editorfunktionen lesen den ganzen Puffer im 100–250-ms-Timer; Einstellungsrecord im Zeichenpfad · Schweregrad: Hoch · Aufwand: M
**Fundstelle:** `IDE/Editor/Atlas.IDE.Editor.LineChanges.pas`, Zeile 97 (`TickMs = 150`), `Track` Zeile 428; `IDE/Editor/Atlas.IDE.Editor.GutterColumn.pas`, Zeile 249 (100 ms), `Track` Zeile 391; `IDE/Foundation/Atlas.IDE.Foundation.GutterMarks.pas`, Zeile 215 (100 ms), `Track` Zeile 364; `IDE/Editor/Atlas.IDE.Editor.MetricsLens.pas`, Zeile 130 (250 ms), `Tick` Zeile 210; `IDE/Editor/Atlas.IDE.Editor.OverviewRuler.pas`, Zeile 437; `IDE/Editor/Atlas.IDE.Editor.Pairs.pas`, Zeile 401 (`PaintText`). Vorgaben: `Atlas.Core.Settings.Plugin.pas`, Zeile 1235, 1358, 1360, 1385.
**Beobachtung:**
```pascal
// LineChanges.Track, jeder Takt (150 ms), auch ohne Tastendruck:
Text := TAtlasEditorBuffer.Text(AView.Buffer);
if Text <> FText then
// GutterColumn.Track, 100 ms:
Text := TAtlasEditorBuffer.Text(View.Buffer);
if not SameText(FFileName, View.Buffer.FileName) or (FText <> Text) or ...
// Pairs.PaintText (je gezeichnetem Textlauf):
ColorsOn := TAtlasIdeSettings.Current.PairColors and ...
```
**Warum das ein Problem ist:** Mit P-04 wurde `TAtlasEditorSnapshots` eingeführt, das den Puffer nur bei gesetztem Dirty-Flag liest. Die seitdem hinzugekommenen Funktionen nutzen es nicht. Mit den Vorgaben sind `GitGutter`, `GutterColumn`, `Metrics` und `OverviewRuler` aktiv; das ergibt bei ruhender IDE grob 30 vollständige Pufferkopien und -vergleiche pro Sekunde im Hauptthread, bei 1–2-MB-Units zweistellige Megabyte je Sekunde. `TAtlasIdeSettings.Current` liefert eine Kopie des Einstellungsrecords mit inzwischen ≈ 340 Feldern, davon 75 Strings; in `Pairs.PaintText` geschieht das je Textlauf, also mehrfach je Zeile und Repaint – exakt das Muster, das in P-10 behoben wurde. Insgesamt laufen im IDE-Layer ≈ 29 Polling-Timer, viele mit 100–250 ms.
**Empfehlung:** Alle `Track`-Methoden auf `TAtlasEditorSnapshots.Get` umstellen und `Version` statt Text vergleichen. Für Malpfade Boolean-Klassenabfragen wie `TAtlasIdeSettings.InlayHintsOn` anbieten (`PairColorsOn`). Mittelfristig einen gemeinsamen Editor-Takt (ein Timer, Abonnenten), der bei `Application.Active = False` pausiert. Absicherung: eine Prüfung in `Tools/Check-*.ps1`, die `TAtlasEditorBuffer.Text(` außerhalb von `EditorSnapshot` meldet und `TAtlasIdeSettings.Current` in Methoden namens `Paint*` verbietet – damit P-04/P-10 nicht ein drittes Mal wiederkommen.
**Konfidenz:** hoch (Code gelesen); Kosten je Sekunde geschätzt.

#### P-16 · MCP blockiert die Nachrichtenschleife – jetzt bis zu 30 Minuten · Schweregrad: Mittel · Aufwand: S (Rest eines alten Befunds, verschlechtert)
**Fundstelle:** `Atlas.Common.Mcp.Server.pas`, Zeile 267 (`tools/call` per `RegisterRequest`); `Atlas.Common.Mcp.IdeBuilds.pas`, Zeile 51 (`BuildMs = 30 * 60 * 1000`); `Shell.Mcp.pas`, Zeile 287 (`Sleep(TMcpIdeBuilds.PollMs)`).
**Beobachtung:** Das Intervall wurde wie empfohlen von 20 auf 50 ms erhöht, aber `tools/call` ist weiter ein synchroner Handler. Das neue Werkzeug für IDE-Builds wartet im selben Thread bis zu 30 Minuten.
**Warum das ein Problem ist:** In dieser Zeit beantwortet der MCP-Server weder `ping` noch `$/cancelRequest`; ein Client mit kürzerem Zeitlimit hält den Server für tot und startet ihn neu.
**Empfehlung:** `tools/call` über `RegisterConcurrentRequest` registrieren – der Dispatcher kann das bereits – und im Polling das Abbruchtoken prüfen.
**Konfidenz:** hoch.

#### P-03 · Regel-Ableitungscache endet am Resolver · Schweregrad: Mittel · Aufwand: S (Rest)
**Fundstelle:** `Rules.Builtin.RtlPatterns.pas`, Zeile 268–276; ebenso `Rules.Builtin.Unresolved`, `Rules.Builtin.Deprecated`.
**Beobachtung:**
```pascal
if Resolver = nil then
begin
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  Resolver.Namespaces := AContext.Namespaces;
end;
Local := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, [Name], Tokens[Start].Offset, False);
```
**Warum das ein Problem ist:** `TRuleDerived` teilt UnitIndex, Routinen und Graphen, aber jede Regel mit Namensauflösung legt einen eigenen Resolver an, und `RtlPatterns` pinnt ihn nicht – je Fund zwei vollständige Extraktionen, das P-01-Muster in den Regeln. Dazu nutzen die Regeln `Walk` nur zweimal; 80 handgeschriebene Rekursionen sind geblieben (relevant für F-03).
**Empfehlung:** Einen gepinnten Resolver als Eintrag im `IRuleDerivedCache` anbieten, den `Unresolved`, `Deprecated` und `RtlPatterns` gemeinsam nutzen. Die Rekursionen mit F-03 auf einen iterativen `Walk` umstellen.
**Konfidenz:** hoch.

#### P-05 · Mitgliedersuche je Vorfahrenstufe weiter linear · Schweregrad: Mittel · Aufwand: M (Rest)
**Fundstelle:** `NameResolver.pas`, `CollectMembers` ab Zeile 2384, `DefaultProperty`, `OverridableMembers`, `AccessorCandidates`, `MissingInterfaceMembers`.
**Beobachtung/Empfehlung:** Das Namensverzeichnis `SymbolsNamed` ist nach Namen geschlüsselt. Für „alle Mitglieder von `TForm` samt Vorfahren“ braucht es ein Verzeichnis nach Container (`SymbolsIn(TypeName)`), das im selben `PrepareNames` mit aufgebaut werden kann.
**Konfidenz:** hoch.

#### P-11 · Statische Regex-Aufrufe je Anfrage · Schweregrad: Mittel · Aufwand: S (Rest)
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas`, Zeile 3053, 3138, 3150, 3301, 3317, 4020, 4047; `CompletionEnums.pas:424`; `Anonymizer.pas:299`; `DfmProperties.pas:392`. Common insgesamt 64 statische `TRegEx.Match`/`IsMatch` (vorher 51).
**Empfehlung:** Konstante Muster als vorkompilierte Instanzen; eine Prüfung im Skript, die `TRegEx.Match(`/`TRegEx.IsMatch(` mit Literalmuster in `Atlas.Common.Lsp.*` meldet.
**Konfidenz:** hoch.

### 4.3 Threadsicherheit (T)

Geteilte Daten und ihr Schutz sind in Anhang 8.3 tabellarisch aufgeführt. Die Grundarchitektur (Lese-Thread ohne Objektbesitz, Momentaufnahmen, `TAtlasMainThread` mit Besitzer-Thread) ist unverändert solide; die Befunde betreffen neue Zugriffspfade.

#### T-01 · `NamingFor` liest `FWorkspaces` ohne Sperre aus Completion-Workern · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Shell.Composition.pas`, Zeile 1096–1103 (eingeführt in `cad79342`).
**Beobachtung:**
```pascal
FCompletion.NamingFor :=
  function(const AUri: string; AKind: TNamingKind): string
  ...
  begin
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
```
**Warum das ein Problem ist:** `WorkspaceOf` iteriert über `FWorkspaces` und kann über `ChooseProject` in `FProjectChoices` schreiben. Alle anderen Aufrufer halten `FWorkspacesLock`; dieser läuft aus dem Thread-Pool ohne. Gleichzeitiges `AddWorkspace`/`RemoveWorkspace` (Ordnerwechsel im Editor) ergibt ein Rennen auf einer `TObjectList` – im harmlosen Fall eine `EListError`, im schlimmen ein Zugriff auf einen freigegebenen Workspace.
**Empfehlung:** Über `SettingsFor`/`PickWorkspace` gehen, die bereits sperren, oder `TMonitor.Enter(FWorkspacesLock)` um den Zugriff. Langfristig `WorkspaceOf` selbst sperren lassen und die Variante ohne Sperre `WorkspaceOfLocked` nennen – dann kann der Fehler nicht wieder unbemerkt entstehen.
**Konfidenz:** hoch.

#### T-02 · Neue Hintergrunddienste lassen hängende Threads beim Entladen mit `FreeOnTerminate` weiterlaufen · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `IDE/Welcome/Atlas.IDE.Welcome.Issues.pas`, Zeile 276–289 (`ReleaseThread`); `IDE/Welcome/Atlas.IDE.Welcome.TestResults.pas`, Zeile 244–257; `IDE/Welcome/Atlas.IDE.Welcome.Setup.pas`, Zeile 286–297 (`Stop`); `Core/Vcs/Atlas.Core.Vcs.Worker.pas`, Zeile 160–180 (`Stop`). Soll-Muster: `Core/Diagnostics/Atlas.Core.Diagnostics.ThreadList.pas`, Zeile 3–10 (#886).
**Beobachtung:**
```pascal
if AWait and not FThread.Finished then
  TAtlasShutdown.WaitForThreads([FThread]);   // höchstens StopMs = 1000
if FThread.Finished then
  FreeAndNil(FThread)
else if AWait then
begin
  FThread.FreeOnTerminate := True;            // Thread läuft mit Code aus dem Package weiter
  FThread := nil;
end;
```
**Warum das ein Problem ist:** Der Kopf von `ThreadList` beschreibt genau diesen Absturz (#886): Ein Thread mit `FreeOnTerminate` gibt nach dem Entladen seine anonyme Methode frei, `rtl370.bpl` liest aus nicht mehr geladenem Speicher. `TAtlasThreadList` wurde am 21.10. eingeführt, aber nur im `CodeInsight.Manager` verwendet; Issues (#765), TestResults (#763) und Setup (#759) vom 16.10. wurden nicht umgestellt. `Vcs.Worker` reiht außerdem mit `TThread.Queue(Current, …)` statt über `TAtlasMainThread` ein, eine Ausnahme in `Done()` läuft dann ohne `TAtlasGuard` in `Application.HandleException`. `Check-MainThreadQueue.ps1` erkennt das nicht, weil es nur `Queue(nil` sucht.
**Empfehlung:** Alle Hintergrunddienste über eine gemeinsame `TAtlasThreadList` starten, deren `StopAll` im gestuften Abbau (`TAtlasTeardown`) läuft. In `Vcs.Worker` über `TAtlasMainThread.Queue(Feature, …)` zustellen. `Check-MainThreadQueue.ps1` um `TThread.Queue(` und `FreeOnTerminate := True` außerhalb von `TimeLimit`/`ThreadList` erweitern.
**Konfidenz:** hoch für den Mechanismus; mittel für die Häufigkeit (die HTTP-Abfragen brechen in 50-ms-Schritten ab).

#### T-03 · Sitzung wird freigegeben, obwohl ein Zeitlimit-Arbeiter noch darin stecken kann · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.pas`, Zeile 629–634 (`StopSessionNow`); `RunningSession`.
**Beobachtung:**
```pascal
  // Aufgegebene Zeitlimit-Arbeiter können noch in Prepare bzw. Sync der Sitzung stecken (A-01, A-13).
  if not TAtlasTimeLimit.WaitIdle(TAtlasShutdown.StopMs) then
    Diagnose('Sitzung beendet, während ein Zeitlimit-Arbeiter noch lief');
  FCommandIdle.WaitFor(5000);
  FServerCommandsIdle.WaitFor(5000);
  FreeAndNil(FSession);
```
**Warum das ein Problem ist:** Nach einer Sekunde wird nur protokolliert, dann folgt `FreeAndNil`; die Rückgabewerte der `WaitFor`-Aufrufe werden ignoriert. `RunningSession` liest `FStopping`, `FServer` und `FSession` aus Arbeiterthreads ohne Sperre oder Barriere – ein Arbeiter kann die Prüfung kurz vor `FStopping := True` passieren. Das Fenster ist viel kleiner als beim alten A-01, aber es ist dieselbe Use-after-free-Klasse, und sie tritt beim Serverneustart auf, also genau dann, wenn ohnehin etwas schiefgelaufen ist.
**Empfehlung:** Ist nach `WaitIdle` noch ein Arbeiter beschäftigt, die Sitzung in eine Liste „ausgemustert“ verschieben (wie `FRetiredResolvers` im Server) und erst beim Entladen freigeben. `FSession`/`FStopping` per `TInterlocked` lesen und setzen.
**Konfidenz:** hoch für den Mechanismus; Annahme zur Häufigkeit.

#### A-06 · Watchdog: nicht kooperierende Handler belegen weiter den Default-Pool · Schweregrad: Mittel · Aufwand: M (Rest)
**Fundstelle:** `Atlas.Common.JsonRpc.Connection.pas`, Zeile 379 (`TTask.Run`).
**Beobachtung/Empfehlung:** Die Antwort beim Zeitlimit ist erledigt. Offen ist der eigene `TThreadPool` mit begrenzter Größe statt `TThreadPool.Default` – das ist mit F-04 zusammen relevant, weil ein Thread nach `EStackOverflow` nicht mehr verwendet werden sollte, was im Default-Pool nicht steuerbar ist.
**Konfidenz:** hoch.

### 4.4 Ressourcen (R)

Geprüft und ohne wesentlichen Befund: GDI-Handles in den neuen Owner-Draw-Fenstern (Welcome, UnitSearch, LineChanges-Painter) – alle in `try/finally`; `TTimer.Create(nil)` 36-mal neu, alle mit `Free`; 10 neue `TApplicationEvents`, alle freigegeben. Notifier-Bilanz im neuen Code: `AddNotifier` 10/10, `AddEditorEventsNotifier` 13/13 (alle mit Interface-Feld), `RegisterDockableForm` 1/1, Willkommensseiten-Plugin 1/1. Die Fixes #1091 und #1093 sind in sich vollständig.

#### R-01 · OTA-Notifier nur als rohe Objektzeiger gehalten, ohne eigene Interface-Referenz und ohne `Destroyed` · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `IDE/Welcome/Atlas.IDE.Welcome.Continue.pas`, Felder Zeile 95–98, Start 362–373, `Stop` 400–416; `IDE/Commands/Atlas.IDE.Commands.QuickOpen.pas`, Zeile 467–472, 487–490; `IDE/Editor/Atlas.IDE.Editor.NavHistory.pas`, Zeile 312–314. Gegenbeispiel: `IDE/Editor/Atlas.IDE.Editor.UnitRename.pas`, Zeile 266–271, 285–293 (`FNotifierRef`).
**Beobachtung:**
```pascal
FNotifier: TIdeNotifier;                           // Klassentyp, keine Interface-Referenz
...
FNotifierIndex := Services.AddNotifier(FNotifier); // nur die IDE hält den Refcount
...
FNotifier.FOwner := nil;                            // Stop: schreibt in das Objekt
if (FNotifierIndex >= 0) and ... then
  Services.RemoveNotifier(FNotifierIndex);
```
**Warum das ein Problem ist:** Das Objekt lebt nur durch die Referenz der IDE. Gibt die IDE es vor dem Entladen von Atlas frei – genau so verhielt sie sich mit den Willkommensseiten-Plugins (#1091) –, schreibt `Stop` in freigegebenen Speicher. `TIdeNotifier` und `TEditNotifier` überschreiben `Destroyed` nicht. Die neueren Units (`UnitRename`, `IdleGate`, `OpenBuild`) halten dagegen `FNotifierRef`; das Muster ist im neuen Code uneinheitlich.
**Empfehlung:** Eine kleine Hilfsklasse `TAtlasIdeNotifierSlot<T>` (Add, Remove, Destroyed, Interface-Feld) einführen und die drei Varianten darauf umstellen; `Destroyed` setzt den Rückzeiger und den Index zurück.
**Konfidenz:** mittel – ob die IDE diese Notifier vor dem Entladen freigibt, ist nicht gemessen; die Inkonsistenz ist sicher.

### 4.5 Plattform, DPI und Kompatibilität (X)

Geprüft und ohne wesentlichen Befund: 64-Bit (Plugin für Win32 und Win64, `LIBSUFFIX AUTO`, keine `Integer`-Casts auf Zeiger in den gelesenen Units), Lokalisierung (Oberflächentexte zentral in `Atlas.UI.Strings`, de/en), VCL-Styles der Popups (Farben über `Atlas.Core.Style.Palette`).

#### X-01 · Keine Bereichs- und Überlaufprüfung in irgendeiner Debug-Konfiguration · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** alle sieben `.dproj` (`Atlas.Text`, `Atlas.Common`, `Atlas.Windows`, `Atlas.IDE.Expert`, `AtlasServer`, `AtlasSetup`, `Atlas.Tests`): weder `DCC_RangeChecking` noch `DCC_IntegerOverflowCheck` gesetzt; im Quelltext nur in drei Produktiv-Units lokale `{$R…}`-Direktiven.
**Beobachtung:** Der Debug-Block von `Atlas.Tests.dproj` setzt `DCC_Define`, `DCC_Optimize=false`, Stack-Frames und Map-Datei, aber keine Prüfungen.
**Warum das ein Problem ist:** Ein Projekt dieser Größe mit viel Index-, Offset- und Positionsrechnung (Zeilen, UTF-16-Spalten, Byte-Offsets, `Copy`/`Pos` mit 1-basierten Indizes) lebt davon, dass Off-by-one-Fehler früh auffallen. Ohne `$R+` laufen Zugriffe hinter Array-Grenzen in den 5 397 Tests still durch – F-01 wäre mit `$R+` im ersten Testlauf nach `8f6394c1` als `ERangeError` aufgefallen, wenn ein Test uses-Vervollständigung und Import-Vorschläge nacheinander ausführt.
**Empfehlung:** In der Debug-Konfiguration aller Projekte `DCC_RangeChecking=true` und `DCC_IntegerOverflowCheck=true`, mindestens im Testprojekt und in `Atlas.Common`. Bewusste Überläufe (Hashes wie FNV-1a im Cache) lokal mit `{$Q-}`/`{$R-}` klammern und kommentieren. Release bleibt ohne Prüfung. Erwartung: Der erste Testlauf findet einige echte Fehler – das ist der Zweck.
**Konfidenz:** hoch.

#### X-02 · Mehrfach-Cursor: feste 2-px-Caret-Breite; je Markierung, Zeile und Repaint ein neuer Memory-DC samt Bitmap · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `IDE/Editor/Atlas.IDE.Editor.MultiCursor.pas`, Zeile 67 (`CaretWidth = 2`), 228–251 (`Blend`), `PaintLine` ab 1095 (Caret 1155–1160).
**Beobachtung:**
```pascal
CaretWidth = 2;
...
Memory := CreateCompatibleDC(ADC);
Bitmap := CreateCompatibleBitmap(ADC, 1, 1);   // je Blend-Aufruf
```
**Warum das ein Problem ist:** Bei 200 % sind die Neben-Carets 2 px breit, das Haupt-Caret der IDE skaliert. Bei vielen Carets entstehen je Zeile mehrere DC/Bitmap-Paare pro Repaint (kein Leck, aber GDI-Last im Zeichenpfad). `LineChanges` zeigt die richtige Lösung (`MulDiv(3, Rect.Height, 16)`, Zeile 695).
**Empfehlung:** Breite aus `Rect.Height` oder `SPI_GETCARETWIDTH` skaliert; den 1×1-DC einmal je `PaintLine` oder als Feld.
**Konfidenz:** hoch.

### 4.6 Code-Smells (S)

Geprüft und ohne wesentlichen Befund: `with` (0), `Application.ProcessMessages` (0), leere `except`-Blöcke (18, alle kommentiert und auf Protokoll-/Beendigungspfade beschränkt), offene `TODO`/`FIXME` (0 – alle Treffer sind Beschreibungen der TODO-Funktion selbst), `{$WARN … OFF}` (2, begründet, mit `DEFAULT`).

#### S-09 · Plugin-Composition: Feature-Tabelle für Start/Stop, daneben handgepflegte Listen für Theme und Einstellungen · Schweregrad: Mittel · Aufwand: M
**Fundstelle:** `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.pas`, `AddFeatures` Zeile 3232–3681 (450 Zeilen), `Register` 3737 (`OnThemeChanged` 3752–3777, `TAtlasIdeSettings.OnChanged` 3799–3860), `Unregister` 3885, `StopWelcome` 3182, `RegisterPalette` (385 Zeilen).
**Beobachtung:**
```pascal
TAtlasIdeSymbol.OnThemeChanged := procedure begin
  ... TAtlasIdeLineChanges.ThemeChanged; TAtlasIdeOverviewRuler.ThemeChanged;
  TAtlasIdeMinimap.ThemeChanged; end;
TAtlasIdeSettings.OnChanged := procedure begin
  RegisterFeatures; ... TAtlasIdeLineChanges.ApplySettings;
  TAtlasIdeOverviewRuler.ApplySettings; TAtlasIdeMinimap.ApplySettings; ...
```
**Warum das ein Problem ist:** Die Tabelle aus der S-03-Empfehlung existiert (`TAtlasFeatureTable`), wird aber nur für Start und Stop genutzt. Theme-Wechsel (15 Einträge), Einstellungsänderung (≈ 20) und Befehlspalette sind weiterhin handgepflegte Ketten. Ein neues Feature braucht Einträge an drei bis fünf Stellen einer 4 005-Zeilen-Unit mit 191 uses; fehlt der Theme-Eintrag, bleibt es nach einem Theme-Wechsel in alten Farben – das fällt nur manuell in der IDE auf.
**Empfehlung:** `TAtlasFeatureTable.Add` um optionale `OnTheme`-, `OnSettings`- und `Commands`-Einträge erweitern; die Handler iterieren über die Tabelle; `RegisterPalette` wird Teil der Feature-Beschreibung.
**Konfidenz:** hoch.

#### S-01 · Completion: Kaskade umgezogen, Kompatibilitäts-Überladungen, `Analyze` mehrfach · Schweregrad: Mittel · Aufwand: M (Rest)
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas`, `RegisterCases` Zeile 2100 (287 Zeilen), 11 Überladungen mit alten Signaturen (z. B. `OverrideItems`, Zeile 235); `Analyze` Zeile 1680, 3560, 3699, 4029, 4635, 4815.
**Beobachtung/Empfehlung:** Die Reihenfolge der Fälle ist weiterhin Code-Reihenfolge in einer langen Closure-Liste, nur an anderer Stelle. Die 11 alten Signaturen sind eine zweite API, die gepflegt und getestet werden muss – auf `TCompletionRequest` umstellen und entfernen. `Analyze` einmal verzögert im Request ablegen. Die Familie ist von 4 307 auf 4 931 + 4 163 Zeilen in acht Units gewachsen; die Aufteilung je Anliegen (Vorschlag 4.2 Schritt 6 vom 15.10.) ist begonnen, aber nicht abgeschlossen.
**Konfidenz:** hoch.

#### S-02 / S-03 · Kompositionswurzeln · Schweregrad: Mittel (Rest) – siehe A-15
Die Aufteilung in `Wire*`-Methoden und die Trennung Planen/Ausführen sind erledigt; das Wachstum der beiden Wurzeln ist als A-15 zusammengefasst.

#### S-08 · „Meine Issues“ schreibt den Präfix in jedes aktive Formular, dessen Klasse oder Name „Commit“ enthält · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `IDE/Welcome/Atlas.IDE.Welcome.Issues.pas`, Zeile 68 (`WatchMs = 700`), 933–943 (`WatchTick`), 946–966 (`FindMessageMemo`), 968–996 (`FillCommitDialog`).
**Beobachtung:**
```pascal
Form := Screen.ActiveForm;
if (Form = nil) or not (ContainsText(Form.ClassName, 'Commit') or ContainsText(Form.Name, 'Commit')) then
  Exit;
Memo := FindMessageMemo(Form);          // erstes sichtbares, beschreibbares Memo
...
TEditAccess(Memo).Text := Text;
```
**Warum das ein Problem ist:** Auch „Commit Transaction“-Dialoge von Datenbankwerkzeugen oder Commit-Dialoge anderer Experten bekommen `#123 ` ins erste Memo. `FFilled` merkt sich das HWND; bei wiederverwendetem Handle unterbleibt das Füllen. Der Timer läuft alle 700 ms, solange ein Issue aktiv ist.
**Empfehlung:** Whitelist der bekannten Klassennamen der IDE-VCS-Dialoge, `Screen.OnActiveFormChange` statt Polling, oder nur der ohnehin vorhandene Git-Hook.
**Konfidenz:** hoch für den Code; Annahme zu fremden „Commit“-Dialogen im Feld.

### 4.7 Duplikate (D)

#### D-11 · Kopien-Sperre prüft nur Namen; neue Positions- und Prefix/Suffix-Rechner entstehen unter anderen Namen · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** Sperrliste `Tools/Check-PackageDependencies.ps1`, Zeile 194–210. Neue Kopien seit 15.10.: `Atlas.Common.Lsp.ResourceStringCommands.pas:73` (`OffsetOf`), `Atlas.Core.Editor.WrapSelection.pas:92/101` (eigene Zeilentabelle mit Binärsuche), `PositionOf` in `IDE.Editor.WrapSelection:105`, `IDE.Editor.BlockComment:77`, `IDE.Editor.LineMove:89`; zeichenweise Prefix/Suffix-Schleifen neu in `Editing.UsesActions:460`, `Core.Editor.LineMove:393`, `Core.Editor.MultiCursor:345` (jetzt 6 Kopien); dazu 76 × `Split([#10])`, 16 × `Pos(#13#10, …)`, `Lsp.Completion.TextLines`/`RangeText`/`OffsetOf` (D-09-Rest).
**Beobachtung:**
```pascal
  function OffsetOf(const APosition: TTextPosition): Integer;   // ResourceStringCommands.pas:73
  ...
    while (Line < APosition.Line) and (Index <= Length(AText)) do
    begin
      if AText[Index] = #10 then
        Inc(Line);
      Inc(Index);
    end;
    Result := Index - 1 + APosition.Character;
```
**Warum das ein Problem ist:** Die Kopie zählt nur `#10` und weicht damit von `TLineTable` ab, in der ein Offset zwischen CR und LF zum Zeilenende gehört – in CR-only-Dateien liefert sie falsche Offsets. `TTextDiff.CommonPrefixSuffix` gibt es nur für Zeilen-Arrays, nicht für Zeichen, deshalb schreibt jeder neue Editor-Befehl die Schleife selbst. Die Sperre greift für `LineBreakOf`/`SplitLines`/`IsWordChar`, aber nicht für `OffsetOf`/`PositionOf`/`AnonymizeLogLine`/`IsWordStart`.
**Empfehlung:** `TTextDiff.CommonPrefixSuffix` für Strings ergänzen; die Sperrliste um `OffsetOf`, `PositionOf`, `PositionAt`, `TextLines`, `AnonymizeLogLine`, `IsWordStart` erweitern; zusätzlich eine Musterprüfung auf `= #10 then` in Schleifen mit Zeilenzählung (Heuristik, mit Ausnahme-Kommentar).
**Konfidenz:** hoch.

#### D-12 · Eine neue Plugin-Einstellung berührt elf Stellen in zwei Units; der Wächter prüft nur `Save` gegen das Schema · Schweregrad: Mittel · Aufwand: L
**Fundstelle:** `Core/Settings/Atlas.Core.Settings.Plugin.pas`: Feld 870, `Defaults` 1461, `Normalize` 1532, `Load` 2052–2053, `Save` 2402; `UI/Settings/Atlas.UI.Settings.Page.pas`: Feld 482, Property 927, `Create` 1989, `BindControls` 2744, `LoadControls` 4762, `SaveTo` 5178 (Beispiel jeweils `WelcomePageQuickActionsConsole`); Wächter `Tools/Update-ConfigDoc.ps1`, Zeile 495–498. Tasteneinstellungen zusätzlich in `KeyConflicts` 165/301, `KeyMap` 249, `MainMenu` 244, `Bindings.Rebind` 299, `Composition` 1330 (`TypeDefinitionKey`: 18 Vorkommen in 9 Produktiv-Units).
**Beobachtung:**
```pascal
Result.TypeDefinitionKey := 0;                                              // Plugin 1228
TypeDefinitionKey := AStore.ReadInteger('TypeDefinitionKey', Default...);   // Plugin 1772
AStore.WriteInteger('TypeDefinitionKey', TypeDefinitionKey);                // Plugin 2170
FTypeDefinitionKey := AddKey(TAtlasStrings.Text(...EditorTypeDefinition));  // Page 1610
FMarks.Bind(FTypeDefinitionKey, ['TypeDefinitionKey']);                     // Page 2479
FTypeDefinitionKey.Text := ShortCutToText(...);                             // Page 4424
ASettings.TypeDefinitionKey := Integer(TextToShortCut(...));                // Page 4806
```
**Warum das ein Problem ist:** Der Registry-Name steht viermal als Literal (Load, Save, `FMarks.Bind`, Schema). `Update-ConfigDoc.ps1` gleicht nur `Write*` in `Save` mit dem Katalog ab; nicht geprüft werden `Load` gegen `Save`, `Defaults`, `Normalize`, `LoadControls`, `SaveTo` und `FMarks.Bind`. Fehlt eine Stelle, wird eine Einstellung gespeichert, aber nie geladen, oder auf der Seite nicht zurückgeschrieben – erkannt nur, wenn zufällig ein Round-Trip-Test für genau diesen Bereich existiert. Deshalb wachsen sieben Methoden linear mit jeder Einstellung und sind heute 326–564 Zeilen lang. Bei ≈ 340 Feldern und dem aktuellen Tempo ist das der größte Wartungsposten des Plugins.
**Empfehlung:** Vorschlag 5.4 – generierte Feldtabelle aus dem Schema, tabellengesteuertes Laden/Speichern/Vorgaben, Seite bindet über `x-key`. Sofortmaßnahme: den Wächter um „Load liest jeden Schlüssel, den Save schreibt“ und „`FMarks.Bind` kennt nur Katalogschlüssel“ erweitern.
**Konfidenz:** hoch.

#### D-13 · Gliederungsfenster umgeht den gemeinsamen Dockfenster-Helfer und zeigt sich nach „X“ angedockt nicht wieder · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `IDE/Outline/Atlas.IDE.Outline.Window.pas`, Zeile 180–202 (`Show`); Helfer `IDE/Foundation/Atlas.IDE.Foundation.DockWindow.pas`, Kopf Zeile 9–11, `Reveal` 183–205.
**Beobachtung:**
```pascal
Form := Services.CreateDockableForm(Dock);
if Form <> nil then
begin
  Form.FreeNotification(Watch);
  UpdateIcon;
end;
...
Form.Show;
Form.BringToFront;
```
**Warum das ein Problem ist:** Der Helfer dokumentiert selbst, dass das X die Form angedockt samt Dock-Gastgeber versteckt und `Form.Show` sie dann nicht zurückbringt. Das Gliederungsfenster (#537) dupliziert die Logik ohne `Reveal` und ohne Desktop-Registrierung – „Gliederung zeigen“ wirkt nach dem Schließen im angedockten Zustand nicht.
**Empfehlung:** Auf `TAtlasIdeDockWindow` umstellen wie Ergebnis-, Diagnose-, Lesezeichen- und Startfenster.
**Konfidenz:** mittel (abgeleitet aus dem dokumentierten Verhalten, nicht in der IDE nachgestellt).

#### D-03, D-04, D-09 · Inline-Varianten und lokale Helfer · Schweregrad: Mittel (Reste) – in D-11 zusammengefasst.

#### D-07 · UI-Zeichenbausteine: Badge dreimal, mit neuer Abweichung · Schweregrad: Mittel · Aufwand: S (Rest)
**Fundstelle:** Badge mit `* 0.62`: `Completion.Popup:1107`, `Hover.Tip:473`, neu `Outline.Breadcrumbs:441` (15 statt 17 px hoch); Textblock in `Completion.Details:202` und `Hover.Tip`.
**Empfehlung:** `DrawBadge` und `DrawBlock` in `Atlas.UI.Popup.Draw` nachziehen; die Breadcrumbs-Variante ist der Beleg, dass jede neue Kopie wieder abweicht.
**Konfidenz:** hoch.

### 4.8 Architektur und Tests (A)

#### A-14 · 14er-Zyklus in `Atlas.Core` läuft nur über Contract-Kanten, die die Zyklusprüfung ausblendet · Schweregrad: Hoch · Aufwand: S
**Fundstelle:** `Tools/Check-PackageDependencies.ps1`, Zeile 500–505; Kanten: `Atlas.Core.Editor.GutterColumn.pas:22` → `Problems.Contract`; `Atlas.Core.Lsp.Session.pas:46` → `Projects.Contract`; `Atlas.Core.Lsp.Session.pas:43` → `Hover.Contract`; `Atlas.Core.Settings.Plugin.pas:956` → `Generate.Contract`.
**Beobachtung:**
```powershell
if ($CompositionRoots -contains $ownUnit) { continue }
...
foreach ($unit in $entries) {
    if ($unit.Name -match '\.Contract$') { continue }
```
**Warum das ein Problem ist:** Die Begründung im Skriptkopf („Contracts verwenden nur Contracts und schließen darum keinen Zyklus“) gilt auf Unit-Ebene, nicht auf Feature-Ebene: `Lsp` hängt über `Session` an den Contracts von `Hover`, `Projects` und `Problems`, und diese Features hängen über ihren Root-Code wieder an `Lsp`. Mit derselben Metrik wie am 15.10. ist der Core-Zyklus von 5 auf 14 Features gewachsen, das Skript meldet „in Ordnung“. Damit ist das Ziel von A-09 – Core und UI später ohne Codeänderung in ein Runtime-Package auslagern und Features isoliert testen – weiter entfernt als vorher, obwohl die Prüfung grün ist. Die gute Nachricht: Vier Kanten schließen den Zyklus jeweils allein; ohne sie ist `Atlas.Core` azyklisch (nachgerechnet), und zwei davon sind trivial (`Problems.Contract` enthält nur zwei Aliase auf `Lsp.Contract`; `TAtlasProjectContext` wird außerhalb des Contracts im Projects-Feature nicht benutzt).
**Empfehlung:** (1) Contract-Kanten nur auslassen, wenn Quelle **und** Ziel Contracts sind. (2) Die vier Kanten kappen: `GutterColumn` auf `Lsp.Contract` umstellen; `TAtlasProjectContext` und `TAtlasProjectNamingKind` nach `Lsp.Contract`; `NormalizeGroups`/`NormalizeHidden` aus `Generate.Contract` in `Settings` ziehen (der Contract trägt dort ohnehin Logik als Record-Methoden, was die Contract-Inhaltsprüfung nicht sieht, weil sie nur `= class` sucht); `TAtlasHoverData` nach `Lsp.Contract` (die teuerste Kante, weil sie Teil der Sitzungs-API ist). (3) `architecture-contract-content` um Record-Methoden mit Implementierung erweitern.
**Konfidenz:** hoch (Graph berechnet, Kanten gelesen).

#### A-08 · Host leer, Fachcode im Platform-Package – Entscheidung ausstehend · Schweregrad: Hoch · Aufwand: XL (offen)
**Fundstelle:** `docs/Architektur.md`, Zeile 38–44 (Commit `bce17694`); `Application/Source` enthält weiter nur `Shell/`.
**Beobachtung:** Der Befund wurde nicht umgesetzt, sondern `Atlas.Common` „bis auf Widerruf“ umdeklariert; die Doku vermerkt ausdrücklich, dass die Rückfrage an dich unbeantwortet ist. Der betroffene Fachcode (`Lsp`, `Rules`, `Editing`, `Semantics`, `Mcp`) ist seitdem von ≈ 58 000 auf ≈ 101 000 Zeilen in 223 Units gewachsen.
**Warum das ein Problem ist:** Jede Woche ohne Entscheidung macht den Umbau teurer; gleichzeitig sind die akuten Folgen (Zyklus `Rules ⇄ Editing`, Monolith-Shell) inzwischen teilweise anders gelöst. Das Thema ist deshalb keine Dringlichkeit mehr, aber eine offene Weiche.
**Empfehlung:** Siehe 5.6 – eine bewusste Entscheidung zwischen „umdeklarieren und festschreiben“ und „Hosted-Features“ treffen und als ADR festhalten.
**Konfidenz:** hoch.

#### A-15 · Kompositionswurzeln mit über 4 000 Zeilen, von Zyklus- und Rollenprüfung ausgenommen · Schweregrad: Mittel · Aufwand: M
**Fundstelle:** `Shell.Composition.pas` (4 692 Zeilen, 88/74 uses, 32 `FCommands.Register`, 99 Methoden; Refactoring-Fachlogik: `ChangeSignature`, `MoveClass`, `InvertBoolean`, `PropertyFromAccessors`, `ExplicitTypeActions`, `Unwrap`, `PasteUses`, `ApplyDfmPropertyRules`; zweites Build-Backend `CompileWithIde`/`CompileWithDcc`); `Atlas.IDE.CodeInsight.Composition.pas` (4 005 Zeilen, 191 uses); Ausnahmen: `$CompositionRoots` in `Check-PackageDependencies.ps1` und `"Atlas.IDE.CodeInsight.Composition -> Atlas.Core.*"` in `atlas.json`.
**Beobachtung:** A-09 und A-10 wurden behoben, indem alle Verstöße in je eine Unit gezogen wurden, die die Prüfungen nicht mehr sieht. Formal ist das konzepttreu (die Host-Shell darf Providers und Adapters importieren), praktisch entstehen zwei 4 000-Zeilen-Units ohne Schutz vor weiterem Wachstum. `Shell.Composition` ist seit dem letzten Review um 75 % gewachsen, obwohl S-02 als erledigt gemeldet wurde.
**Warum das ein Problem ist:** Jede neue Funktion landet zuerst dort, weil es der einzige Ort ist, an dem alles erreichbar ist. Fachlogik in der Composition (z. B. die Refactoring-Actions) ist nicht ohne Server testbar – `Tests/Application` hat zehn Units für 10 391 Zeilen.
**Empfehlung:** (1) Statt der Pauschalausnahme `Atlas.Core.*` nur die Rollen `Providers`, `Adapters`, `Composition` erlauben – dann fällt ein Import von Core-Root-Code wieder auf. (2) Eine Größengrenze für Kompositionswurzeln im Skript (z. B. Warnung über 2 000 Zeilen). (3) Die Refactoring-Actions aus `Shell.Composition` in eine Feature-`Composition` je Refactoring-Familie (`Atlas.Common.Lsp.Refactorings.Composition`) ziehen, die die Shell nur noch aufruft – das ist zugleich der erste Schritt von 4.5 vom 15.10., unabhängig von der Entscheidung zu A-08.
**Konfidenz:** hoch.

#### A-09 / A-10 · Namensschema und genehmigte Ausnahmen · Schweregrad: Mittel (Reste)
A-09: Das Plugin-Namensschema (`Atlas.Core`/`Atlas.UI`/`Atlas.IDE` statt `Atlas.IDE.Expert.…`) bleibt eine dokumentierte Ausnahme (`Architektur.md:112`); der Zyklus ist nach Core gewandert (A-14). A-10: Die 18 verbleibenden Treffer sind alle als genehmigte Ausnahmen in `atlas.json` eingetragen; für `TDfmObject`/`TDfmDocument` im Contract und `Documents.Contract → Atlas.Text.Lines` ist das vertretbar, die Pauschalausnahme der Plugin-Wurzel nicht (A-15).

#### Tests und Testbarkeit
Die Testbasis hat sich verdoppelt (508 Units, 5 397 Tests), `Check-TestCoverage.ps1` erzwingt eine Testunit je Logik-Unit, Gleichlauftests sichern `Atlas.Text` zwischen Server und Plugin ab. Lücken: (1) `Tests/Application` mit zehn Units für 10 391 Zeilen Shell – `WireCommands`, `ChooseProject`, `CompileWithIde`, `NamingFor` (T-01) sind ungetestet. (2) Keine Tests für die Fälle, die heute zum Absturz führen: tiefe Operatorketten über alle Regeln (F-03), verschachtelter Typ in `strict private` (F-02), Datei mit Fehler in `workspace/diagnostic` (F-04). (3) Kein Test, der zwei Aufrufer desselben Index-Snapshots kombiniert (F-01). (4) Bereichsprüfung aus (X-01). Diese Tests gehören im Fahrplan **vor** die jeweiligen Korrekturen.

### 4.9 Dokumentation (K)

Die Dokumentationskultur ist unverändert hoch: Kopfkommentare mit Warum und Issue-Nummer auch im neuen Code, ADR 0011 und 0012 neu, `/// <summary>`-Dichte im Plugin gestiegen, README beschreibt den gesamten Funktionsumfang, `Check-DocComments.ps1` neu. Die Übergabe-Notizen in `docs/Uebergabe.md` sind präzise und haben dieses Review erheblich erleichtert (EStackOverflow-Notiz, A-08-Vermerk).

#### K-07 · `Core.Welcome.IndexFiles` nennt Cache-Format 16, die Konstante ist 18 · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Atlas.Core.Welcome.IndexFiles.pas`, Kopfkommentar und Zeile 47; `Atlas.Common.Index.Cache.pas`, Zeile 76.
**Warum das ein Problem ist:** Die Unit (523 Zeilen) liest das Cache-Format des Servers im Plugin nach – eine weitere Kopie über die Paketgrenze, die bei jedem `FormatVersion`-Sprung mitgezogen werden muss; der Kopf ist schon zwei Versionen hinterher.
**Empfehlung:** Zahl aus dem Kommentar streichen; einen Gleichlauftest wie bei `Atlas.Text` ergänzen, der die Plugin-Konstante gegen `TIndexCache.FormatVersion` prüft, oder das Lesen der Köpfe nach `Atlas.Text` verlagern.
**Konfidenz:** hoch.

#### K-08 · `Atlas.Text` wächst über den Rahmen von ADR 0012 hinaus · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Packages/Atlas.Text/Source/{DUnitX, TestResults, Checkin, Defines}`; `Atlas.Text.DUnitX` 1 083 Zeilen (`TDUnitXSource.Scan` 480 Zeilen), `TestResults` 613; `docs/adr/0012-gemeinsamer-text-code.md`, Punkt 2 und 4.
**Warum das ein Problem ist:** ADR 0012 begründet `Atlas.Text` als kleinen, reinen Textcode; DUnitX-Quellanalyse, Testergebnis-Parser und Checkin-Logik sind Fachcode. Nach Punkt 4 wandert jede neue Unit auch ins IDE-BPL. Ohne Abgrenzung wird `Atlas.Text` das nächste Sammelbecken.
**Empfehlung:** ADR 0012 fortschreiben: was in `Atlas.Text` darf (Kriterium: von Server **und** Plugin gebraucht, ohne Fachbegriff), und die vier Units dort entweder ausdrücklich aufnehmen oder als eigenes kleines Feature ausweisen.
**Konfidenz:** hoch.

---

## 5. Verbesserungsvorschläge mit Konzept

Sechs Maßnahmen, nach Nutzen und Aufwand sortiert. Die Codeskizzen sind für Delphi 12 geschrieben (kein `if`-Ausdruck, kein `is not`/`not in`) und konnten ohne Atlas nicht mit `check_code` geprüft werden; sie sind als Gerüst zu lesen.

### 5.1 Den offenen Absturz beenden: Stapeltiefe, Wiedereintritt, Fehler je Datei, Snapshot-Kopie  (Nutzen: sehr hoch · Aufwand: S–M)

**Ziel.** Kein Serverneustart mehr durch `EStackOverflow`; eine einzelne problematische Datei verhindert weder die Diagnose der übrigen Dateien noch reißt sie den Prozess mit; der Import-Namensindex zeigt nie auf falsche Units. Erfolg: das Atlas-Repo selbst läuft eine Stunde mit `workspace/diagnostic` ohne Neustart; die neuen Tests sind grün mit `$R+`.

**Ist.** F-01, F-02, F-03, F-04, X-01; teilweise P-03 (80 rekursive Läufer), A-06 (Default-Pool).

**Soll.**

```pascal
// F-04 – PullDiagnostics.CollectWorkspace: Fehler je Datei, nicht je Runde
for Uri in Files do
begin
  TRequestDiagnostics.Note('file', Uri);              // Eingrenzung im Diagnoselog
  try
    Items := CachedDiagnose(Uri, ResultId, Disk, ACancellation);
  except
    on E: EOperationCancelled do
      raise;
    on E: Exception do
    begin
      FLogger.Warning(Format('Diagnose für %s fehlgeschlagen: %s', [Uri, E.ClassName]));
      if E is EStackOverflow then
        FPoisoned.Add(DocumentKey(Uri, Version));     // diese Dateiversion nicht erneut rechnen
      Items := nil;                                   // leerer Bericht, Runde läuft weiter
    end;
  end;
  Result.Add(Uri, ResultId, Items);
end;

// F-02 – NameResolver.CurrentClass: Wiedereintritt sperren
if FClassState = 0 then
begin
  FClassState := 1;
  if (FTree <> nil) and MethodClass(FClass) then
    FClassState := 2;
end;

// F-03 – SyntaxTree.Walk iterativ
procedure TSyntaxNode.Walk(const AVisit: TSyntaxNodeVisit);
var
  Stack: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Stack := TStack<TSyntaxNode>.Create;
  try
    Stack.Push(Self);
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if not AVisit(Node) then
        Continue;
      for Index := Node.ChildCount - 1 downto 0 do     // rückwärts, damit die Reihenfolge erhalten bleibt
        Stack.Push(Node.Children[Index]);
    end;
  finally
    Stack.Free;
  end;
end;

// F-01 – SymbolIndex.Units: Kopie der Referenzliste
Result := Copy(FUnitsSnapshot);
```

**Absicherung durch Tests (vorher schreiben).** (1) `Units` zweimal holen, das erste sortieren, das zweite unverändert (F-01). (2) `TA = class strict private type TB = class procedure X; end; end;` und `Resolve` im Rumpf (F-02) – mit Zeitlimit, damit der Test nicht den Testlauf abschießt. (3) Datei mit 10 000 Summanden durch Parser und jede Builtin-Regel (F-03). (4) `workspace/diagnostic` mit einer Datei, deren Diagnose wirft – die anderen Dateien bekommen ihren Bericht (F-04). (5) `DCC_RangeChecking`/`DCC_IntegerOverflowCheck` im Debug-Testprojekt einschalten (X-01).

**Schritte.**
1. `TRequestDiagnostics.Note('file', Uri)` vor `CachedDiagnose` – eine Zeile, liefert sofort die schuldige Datei aus dem Feld.
2. Tests 1–4 anlegen; erwartetes Ergebnis: rot.
3. F-01 (`Copy`), F-02 (Wiedereintritt) – je wenige Zeilen.
4. F-04: Fehler je Datei, Sperrliste je Dokumentversion.
5. F-03: `Walk` iterativ; die Builtin-Läufer der Reihe nach auf `Walk` umstellen (je Regel ein Commit, Test 3 sichert ab); `TooDeep` in den Binär-Schleifen des Parsers.
6. X-01: Prüfungen im Debug-Testprojekt einschalten, gefundene Fehler beheben, dann auf alle Debug-Konfigurationen ausweiten.
7. Mittelfristig: Operatorketten als n-äre Knoten und eigener Pool (A-06), damit ein Thread nach `EStackOverflow` ersetzt werden kann.

**Aufwand.** Schritte 1–4: S (zwei bis drei Stunden). Schritt 5: M (die Läufer sind mechanisch, aber zahlreich). Schritt 6: S plus unbekannte Zahl gefundener Fehler. **Risiken.** Iteratives `Walk` ändert die Besuchsreihenfolge, wenn ein Läufer sich auf Pre-/Post-Order verlässt – Regeln mit „nach den Kindern“-Logik brauchen eine Variante mit Post-Order (Stack mit Markierung). `$R+` kann bei absichtlichen Überläufen (FNV-1a-Prüfsumme im Cache) auslösen; diese lokal klammern. **Alternativen.** `{$MAXSTACKSIZE}` auf 8 MB erhöhen – verschiebt die Grenze und kostet nichts, ist aber nur ein Pflaster; als zusätzliche Sicherung vertretbar, nicht als Ersatz für Schritt 5. Pool-Threads mit größerem Stack (`TThread.Create` mit `StackSize`) – setzt den eigenen Pool voraus.

### 5.2 Sicherheit: Import, Programmsuche, MCP-Pfade, Inlining  (Nutzen: hoch · Aufwand: S)

**Ziel.** Keine Programmausführung über importierte Einstellungsdateien, aus dem Arbeitsverzeichnis oder über Projekte außerhalb des Arbeitsordners; kein Refactoring, das still falschen Code erzeugt.

**Ist.** F-05, F-07, F-08, F-06.

**Soll.**

```pascal
// F-05 – Settings.Transfer: Sicherung nur nach Ort, nie nach Inhalt
Result.Backup := SameText(ExtractFilePath(AFileName), IncludeTrailingPathDelimiter(BackupFolder))
  and StartsText(BackupPrefix, ExtractFileName(AFileName));

// F-07 – VcsChanges.FindProgram: kein nackter Name als Rückfall
class function TVcsChanges.FindProgram(const AName: string): string;
var
  Dir, Name: string;
begin
  Name := ChangeFileExt(AName, '') + '.exe';
  for Dir in GetEnvironmentVariable('PATH').Split([PathSep]) do
    if (Dir <> '') and TFile.Exists(TPath.Combine(Dir.Trim(['"']), Name)) then
      Exit(TPath.Combine(Dir.Trim(['"']), Name));
  Result := '';
end;

// F-08 – Mcp: Pfade nur unterhalb des Arbeitsordners
class function TMcpPaths.InsideRoot(const ARoot, APath: string): Boolean;
var
  Root: string;
begin
  Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(ARoot));
  Result := StartsText(Root, TPath.GetFullPath(APath));
end;
```

**Absicherung.** Je ein Test: Import mit `"backup": true` außerhalb des Sicherungsordners übernimmt keinen `x-machine`-Wert; `FindProgram('git')` und `FindProgram('git.exe')` liefern denselben Pfad, bei leerem PATH `''`; `run_tests` mit `..\..\x.dproj` wird abgelehnt; `/inline` auf einem Aufruf einer gleichnamigen Methode einer anderen Klasse lehnt ab.

**Schritte.** 1. F-07 (eine Zeile plus `FindProgram`). 2. F-05 (Sicherung nach Ort; `quickActions.console` und `help.reportFolder` als `x-machine` im Schema; `Update-ConfigDoc.ps1`). 3. F-08 (`InsideRoot` in `run_tests`, `build_project` und allen schreibenden Werkzeugen). 4. F-06 (`InlineMethod` ohne `Lookup` ablehnen; den Slash-Host später mit Resolver versorgen).

**Aufwand.** S (zusammen gut eine Stunde plus Tests). **Risiken.** Bestehende Sicherungen außerhalb des Standardordners lassen sich nicht mehr vollständig zurückspielen – in der Meldung nennen. Nutzer, die `/inline` bisher erfolgreich verwendet haben, bekommen eine Ablehnung, bis der Resolver im Slash-Host verfügbar ist. **Alternativen.** Für F-05 eine Signatur der Sicherungsdatei (HMAC mit rechnergebundenem Schlüssel über `CryptProtectData`) – sicherer gegen Manipulation einer echten Sicherung, aber mehr Aufwand als nötig; der Ort genügt, weil der Sicherungsordner unter `%APPDATA%` des Nutzers liegt.

### 5.3 Prüfwerkzeuge dort schließen, wo die Probleme jetzt sitzen  (Nutzen: hoch · Aufwand: S)

**Ziel.** Die Prüfskripte melden die Klassen von Fehlern, die in diesem Review als Nebenwirkung von Erledigungen entstanden sind, damit „erledigt“ wieder „erledigt“ bedeutet.

**Ist.** A-14 (Contract-Kanten ausgeblendet), A-15 (Pauschalausnahme der Wurzel), D-11 (Sperrliste nur nach Namen), T-02 (`Queue(Current` und `FreeOnTerminate` nicht geprüft), P-18 (Pufferlesen und `Settings.Current` im Malpfad), P-11 (statische Regex), D-12 (Wächter nur `Save`).

**Soll – Ergänzungen in `Tools/Check-*.ps1`:**

| Prüfung | Regel | Ausnahmekommentar |
|---|---|---|
| Feature-Zyklen | Contract-Kanten nur auslassen, wenn Quelle **und** Ziel Contract sind | – |
| Kompositionswurzeln | Import aus `Atlas.Core.*` nur für Rollen `Providers`, `Adapters`, `Composition`; Warnung über 2 000 Zeilen | `// composition-ok` |
| Kopien-Sperre | Namen ergänzen: `OffsetOf`, `PositionOf`, `PositionAt`, `TextLines`, `AnonymizeLogLine`, `IsWordStart` | `// copy-ok: Grund` |
| Hauptthread | `TThread.Queue(` und `TThread.Synchronize(` im Plugin außerhalb von `MainThread`; `FreeOnTerminate := True` außerhalb von `TimeLimit`/`ThreadList` | `// mainthread-ok` |
| Editor-Puffer | `TAtlasEditorBuffer.Text(` nur in `EditorSnapshot`; `TAtlasIdeSettings.Current` nicht in Methoden `Paint*` | `// buffer-ok` |
| Regex | `TRegEx.(Match|IsMatch|Matches)(` mit Literalmuster in `Atlas.Common.Lsp.*` | `// regex-ok` |
| Einstellungen | jeder Schlüssel, den `Save` schreibt, wird in `Load` gelesen, hat einen Wert in `Defaults` und – falls `x-control` – ein `FMarks.Bind` | – |
| Contract-Inhalt | `architecture-contract-content` auch für Record-Methoden mit Implementierung | genehmigte Ausnahme in `atlas.json` |

**Absicherung.** Jede neue Prüfung bekommt einen Selbsttest wie `role-imports.json` (ein Positiv-, ein Negativbeispiel), damit das Skript nicht still grün wird.

**Schritte.** 1. Zyklusprüfung korrigieren – sie wird rot (A-14). 2. Die vier Kanten aus A-14 kappen – grün. 3. Die übrigen Prüfungen einzeln ergänzen, jeweils mit den gefundenen Stellen als Arbeitsliste.

**Aufwand.** S je Prüfung; die Arbeitslisten selbst (z. B. P-18, D-11) sind die eigentliche Arbeit. **Risiken.** Viele neue Ausnahmekommentare, wenn die Regeln zu grob sind – lieber eng beginnen. **Alternativen.** Die Prüfungen als Atlas-Regeln statt PowerShell – liefert Diagnosen im Editor und ist dieselbe Infrastruktur, die das Produkt verkauft; für die Rollen- und Contract-Regel ist das bereits geschehen, für die übrigen lohnt es, sobald sie stabil sind.

### 5.4 Plugin-Einstellungen tabellengesteuert aus dem Schema  (Nutzen: hoch · Aufwand: L)

**Ziel.** Eine neue Einstellung entsteht durch einen Eintrag im Schema plus Text in `Atlas.UI.Strings`; Laden, Speichern, Vorgaben, Normalisierung, Seitenbindung und Rückschreiben folgen daraus. Erfolg: die sieben Methoden `Load`, `Save`, `Defaults`, `Normalize`, `Create`, `LoadControls`, `SaveTo`, `BindControls` sind zusammen kürzer als heute eine von ihnen.

**Ist.** D-12, S-09 (dasselbe Muster bei Features), P-18 (Record mit ≈ 340 Feldern im Malpfad).

**Soll.**

```pascal
// generiert von Update-ConfigDoc.ps1 aus atlas-plugin.schema.json, neben PluginSchemaData
type
  TAtlasSettingKind = (Bool, Int, Str, Key, Enum);

  TAtlasSettingField = record
    Key: string;                  // x-key, z. B. 'editor.typeDefinitionKey'
    StoreName: string;            // Registry-Name, z. B. 'TypeDefinitionKey'
    Kind: TAtlasSettingKind;
    DefaultValue: string;
    Min, Max: Integer;
    Get: TFunc<TAtlasPluginSettings, string>;
    SetValue: TProc<PAtlasPluginSettings, string>;
  end;

const
  AtlasSettingFields: array[0..339] of TAtlasSettingField = (...);   // generiert

// Settings.Plugin – Load/Save/Defaults werden Schleifen:
class function TAtlasPluginSettings.Load(const AStore: IAtlasSettingsStore): TAtlasPluginSettings;
var
  Field: TAtlasSettingField;
begin
  Result := Defaults;
  for Field in AtlasSettingFields do
    Field.SetValue(@Result, AStore.ReadString(Field.StoreName, Field.Get(Result)));
  Result.Normalize;
end;

// Settings.Page – Controls werden über x-control und x-key gebunden:
for Field in AtlasSettingFields do
  FControls.Add(Field.Key, CreateControlFor(Field, PageOf(Field.Key)));
```

Konstante Arrays mit anonymen Methoden sind in Delphi nicht möglich; die Getter/Setter werden deshalb im `initialization`-Abschnitt der generierten Unit zugewiesen oder als Feld-Offset (`NativeInt(@PAtlasPluginSettings(nil).TypeDefinitionKey)`) plus `Kind` umgesetzt – Letzteres ist schneller und ohne Closures, aber weniger typsicher; das generierte Skript garantiert die Übereinstimmung.

**Absicherung.** Round-Trip-Test über **alle** Felder: Defaults → Save → Load ergibt Defaults; jedes Feld mit einem Nicht-Standardwert → Save → Load ergibt denselben Wert; jede Seite: LoadControls → SaveTo ergibt unveränderte Einstellungen. Diese Tests vor dem Umbau schreiben – sie laufen gegen den heutigen Code und finden vermutlich schon Lücken.

**Schritte.** 1. Round-Trip-Tests (vor dem Umbau). 2. Generator um die Feldtabelle erweitern. 3. `Defaults`, dann `Load`/`Save` tabellengesteuert, die alten Methoden als Vergleich im Test behalten, bis beide gleich sind. 4. `Normalize` auf Bereichsangaben aus dem Schema. 5. Settings-Seite seitenweise auf Bindung über `x-key` umstellen. 6. Tastenbelegungen (`Rebind`, `KeyMap`, `KeyConflicts`, `MainMenu`) über dieselbe Tabelle (`Kind = Key`).

**Aufwand.** L (drei bis fünf Tage, gut in seitenweise Commits teilbar). **Risiken.** Registry-Namen müssen exakt übernommen werden, sonst verlieren Nutzer Einstellungen – der Generator übernimmt sie aus dem bestehenden `Save`, der Round-Trip-Test sichert ab. Seitenlayout ändert sich, wenn Controls generisch entstehen; Sonder-Controls (Regeltabelle, Snippets) bleiben handgeschrieben. **Alternativen.** RTTI über `TRttiContext` auf den Record – kein Generator nötig, aber Laufzeit-Typinformation widerspricht dem Konzeptziel „Compiler-Sicherheit“ und ist im IDE-Prozess langsamer; der Generator ist vorzuziehen, weil das Schema ohnehin die Quelle ist.

### 5.5 Plugin-Lebensdauer vereinheitlichen: Threads, Notifier, Takt  (Nutzen: mittel · Aufwand: M)

**Ziel.** Es gibt je genau ein Muster für Hintergrund-Threads (`TAtlasThreadList`), Notifier (`TAtlasIdeNotifierSlot<T>`), Dockfenster (`TAtlasIdeDockWindow`), Editor-Takt und Pufferzugriff (`TAtlasEditorSnapshots`) – und neuer Code kann nicht am Muster vorbei.

**Ist.** T-02, T-03, R-01, D-13, P-18, S-09.

**Soll.**

```pascal
type
  TAtlasIdeNotifierSlot<TNotifier: class, IOTANotifier> = record
  private
    FObject: TNotifier;
    FRef: IOTANotifier;          // eigene Referenz: das Objekt überlebt die IDE-Freigabe
    FIndex: Integer;
  public
    procedure Add(const AServices: IOTAServices; ANotifier: TNotifier);
    procedure Remove(const AServices: IOTAServices);
    function Live: TNotifier;    // nil nach Destroyed
  end;

  TAtlasEditorTick = class
  public
    class procedure Subscribe(const AName: string; AIntervalMs: Cardinal; const AOnTick: TProc<IAtlasEditorSnapshot>);
    class procedure Unsubscribe(const AName: string);
    // ein Timer, pausiert bei Application.Active = False, liefert nur bei neuer Version
  end;
```

**Absicherung.** Für `TAtlasThreadList`: Test, der einen hängenden Thread startet und `StopAll` mit kurzer Frist ruft – er darf nicht `FreeOnTerminate` werden, sondern landet in der Liste „ausgemustert“. Für den Takt: Zähler, wie oft `TAtlasEditorBuffer.Text` bei unveränderter Version gelesen wird – muss 0 sein.

**Schritte.** 1. `Issues`, `TestResults`, `Setup`, `Vcs.Worker` auf `TAtlasThreadList`; `Vcs.Worker` auf `TAtlasMainThread`. 2. `TAtlasIdeNotifierSlot` und Umstellung von `Continue`, `QuickOpen`, `NavHistory`. 3. Outline-Fenster auf `TAtlasIdeDockWindow`. 4. `TAtlasEditorTick`; `LineChanges`, `GutterColumn`, `GutterMarks`, `MetricsLens`, `OverviewRuler` umstellen. 5. `TAtlasFeatureTable` um `OnTheme`/`OnSettings`/`Commands` erweitern. 6. Sitzung „ausmustern“ statt freigeben (T-03).

**Aufwand.** M (zwei Tage). **Risiken.** Der gemeinsame Takt ändert das zeitliche Verhalten der Gutter-Funktionen (gleichzeitige statt versetzte Aktualisierung) – sichtbar höchstens als gleichzeitiges Neuzeichnen. **Alternativen.** Nur die Prüfskripte aus 5.3 und die Umstellung bei der nächsten Berührung der jeweiligen Unit – billiger, aber die Altfälle bleiben bis dahin bestehen; für T-02 und P-18 nicht zu empfehlen, weil sie im Normalbetrieb wirken.

### 5.6 Entscheidung zu A-08 treffen und festschreiben  (Nutzen: mittel · Aufwand: S für die Entscheidung)

**Ziel.** Die seit dem 16.10. offene Weiche wird bewusst gestellt; `docs/Architektur.md` enthält keinen Vermerk „Antwort steht aus“ mehr.

**Ist.** A-08; A-15 als Folge.

**Optionen.**

| | (a) Umdeklarieren festschreiben | (b) Hosted-Features in den Host |
|---|---|---|
| Inhalt | `Atlas.Common` gilt als Fachcode-Package (Konzept 6.2), Hosts sind `AtlasServer`, MCP und Linter | `Lsp`, `Rules`, `Editing`, `Semantics`, `Mcp` wandern nach `Application/Source/Features` mit eigener `Composition` |
| Aufwand | ADR schreiben, Prüfskript auf Matrix 8.1/8.2 für `Atlas.Common` umstellen | XL, ≈ 101 000 Zeilen, mehrere Wochen |
| Nutzen | Ehrlich, sofort; die Matrix 8.2 verbietet dann gegenseitige Importe der Features und hätte `Rules ⇄ Editing` von Anfang an verhindert | Konzepttreu im Wortlaut; Fachcode-Package für einen zweiten Host abspaltbar |
| Kosten | `Atlas.Common` bleibt groß; Plattform- und Fachcode im selben Artefakt | Hoher Umbau bei hohem Tempo; Konflikte mit laufenden Feature-Branches |

**Empfehlung.** (a) – jetzt, mit ADR 0013, und die Feature-Matrix 8.2 für die fünf Fach-Features im Prüfskript aktivieren. Die Trennung nach Rollen (eigene `Composition` je Feature, A-15 Schritt 3) bringt den größten Teil des Nutzens von (b) ohne Verschiebung von Dateien. (b) bleibt möglich, falls ein zweiter Host mit anderem Fachcode-Zuschnitt kommt.

---

## 6. Empfohlener Fahrplan

**Sofort (heute/morgen, zusammen unter einem Tag):**
1. 5.1 Schritt 1 – eine Zeile Diagnose (`Note('file', Uri)`), damit der nächste Absturz die Datei nennt.
2. 5.1 Schritte 2–4 – Tests, dann F-01, F-02, F-04.
3. 5.2 komplett – F-07, F-05, F-08, F-06.
4. Quick Wins (je unter einer Stunde): T-01 (`NamingFor` sperren), P-16 (`tools/call` nebenläufig), K-07, F-09, X-02, S-08 (Whitelist), D-13 (Outline auf `TAtlasIdeDockWindow`), die zwei trivialen Kanten aus A-14 (`GutterColumn`, `TAtlasProjectContext`).

**Diese Woche:**
5. 5.1 Schritte 5–6 – `Walk` iterativ, Läufer umstellen, `$R+/$Q+` im Debug-Testprojekt, gefundene Fehler beheben.
6. 5.3 – Prüfskripte schließen; damit werden die Arbeitslisten für P-18, D-11, T-02 sichtbar.
7. 5.6 – Entscheidung zu A-08 treffen.

**Nächstes Release:**
8. 5.5 – Lebensdauer-Muster vereinheitlichen (T-02, T-03, R-01, P-18, S-09).
9. Reste: P-03 (gepinnter Resolver im Regelcache), P-05 (Container-Verzeichnis), P-11, S-01 (Kompatibilitäts-Überladungen entfernen), D-07, A-06 (eigener Pool).

**Langfristig:**
10. 5.4 – Einstellungen tabellengesteuert, beginnend mit den Round-Trip-Tests (die sofort geschrieben werden können und schon vorher Lücken finden).
11. A-15 Schritt 3 – Refactoring-Actions aus `Shell.Composition` in Feature-Compositions.

**Prozess:** Nach jeder Erledigung eines Review-Befunds die Fundstelle **und** die Aufrufer der geänderten API einmal nachprüfen (bei P-13 hätte ein Grep nach `Index.Units` die sortierende Stelle gezeigt) und den Statusblock erst danach auf „erledigt“ setzen. Neue Ausnahmen in Prüfskripten nur mit einem Satz Begründung und Datum.

---

## 7. Was gut ist

Konkrete Stärken, die beibehalten und auf neuen Code übertragen werden sollten.

1. **Die Umsetzungsgeschwindigkeit und -qualität der alten Befunde.** 38 von 53 in sechs Tagen tatsächlich erledigt, meist in der vorgeschlagenen Form und mit Tests – `PinTree` schachtelbar mit Zähler (`NameResolver.pas:2770`), `TCompletionRequest` mit verzögerten Feldern, `TRuleDerived`, `TAtlasEditorSnapshots`, `Atlas.Core.Hover.Layout` VCL-frei mit `LayoutKey`.
2. **`Atlas.Text` mit Gleichlauftests und Sperrliste** (`Packages/Atlas.Text`, ADR 0012, `Tests/IDE.Expert/Atlas.Core.Text.Agreement.Tests.pas`, `Check-PackageDependencies.ps1:194–210`): Die Variante „Quelltext in beide Packages“ hält „ein BPL“ ein und beseitigt die Drift; der Gleichlauftest prüft, dass Server und Plugin dasselbe Ergebnis liefern.
3. **`TAtlasMainThread`** (`Atlas.Core.Diagnostics.MainThread`): ruhender Besitzer-Thread, `RemoveQueuedEvents(Owner)` beim Stopp, jeder Eintrag unter `TAtlasGuard`, erzwungen per Skript und CLAUDE.md. 31 → 0 `Queue(nil, …)`. Das ist die richtige Antwort auf A-02 und S-05 zugleich.
4. **Rollenmatrix als Atlas-Regel mit Selbsttest** (`architecture-role-import`, `architecture-contract-content`, `Tests/Data/Architecture/role-imports.json`, CI): Das Projekt prüft sein eigenes Architekturkonzept mit dem eigenen Produkt.
5. **Zugangsdaten für CI und Tracker** (`Atlas.Core.Ci.Adapters.Credentials.pas:78–131`, `Ci.Adapters.Http.pas:110–135`, `Ci.Internals.Addresses.pas:241–268`): Windows-Anmeldespeicher, Token-Kopien genullt, Authentifizierung nur über https beim eingetragenen Server, Weiterleitungen nur auf denselben Rechner, keine Cookies, `user@host` verworfen, Token-Schlüssel in der Projektdatei `.atlas` verboten.
6. **Prozessaufrufe für git und svn** (`Atlas.Core.Vcs.Adapters.ProcessRunner.pas:133–211`, `Providers.Git.pas:528/537`, `Providers.Svn.pas:319/331`, `Tracker.Naming:195–229`): Argument-Arrays, Quoting nach `CommandLineToArgvW`, `--` als Trenner, Peg-Revision bei svn, Branchnamen nach `check-ref-format`. Der eine Ausrutscher (F-07) liegt im Server, nicht hier.
7. **`Atlas.Common.Semantics.Recursion`** (`CollectRoutines` 337–361, `CollectEdges` 560–605, `PathTo` 614–673): iterativ mit `TStack`, begrenzte Breitensuche – das Vorbild für F-03.
8. **Parser für variante Records (#846)** (`Parser.pas`, `ParseVariantPart` 1595, `ParseVariantBody` 1620, `ParseVariantFields` 1674): `EnterNesting`/`TooDeep` und Fortschrittsschutz `if FIndex = Before then Advance` in jeder Schleife.
9. **`TAtlasIdeDockWindow`** (`Atlas.IDE.Foundation.DockWindow.pas`) mit VCL-freier Entscheidungslogik in `Atlas.Core.Dock.Plan` und Tests; `FreeNotification` auf Form und Frame, `Reveal` über die Gastgeberkette.
10. **OTA-Disziplin im neuen Code**: 10/10 `AddNotifier`, 13/13 `AddEditorEventsNotifier` (alle mit Interface-Feld), 36 Timer und 10 `TApplicationEvents` alle freigegeben; #1091 und #1093 vollständig behoben.
11. **Übergabe-Notizen** (`docs/Uebergabe.md`): präzise, mit offenem Status, Logzeilen und Vermutung. Die EStackOverflow-Notiz hat die Ursachensuche in diesem Review direkt ermöglicht.
12. **Testdichte gehalten** bei verdoppeltem Code (≈ 15 Tests je 1 000 Zeilen), `Check-TestCoverage.ps1` erzwingt eine Testunit je Logik-Unit.

---

## 8. Anhang

### 8.1 Diagnostik

Atlas-Diagnostik und Compiler-Warnungen des letzten Builds konnten in dieser Sitzung nicht abgerufen werden (siehe 8.6). CLAUDE.md verlangt vor jedem Merge 0 Fehler, 0 Warnungen, 0 Hinweise unter Delphi; ob das für `c8f29bc1` erfüllt ist, wurde nicht geprüft.

### 8.2 Musterzählung (Grep, `Packages` und `Application`, ohne Tests)

| Muster | 15.10. | 21.10. | Bewertung |
|---|--:|--:|---|
| `:= X + [`-Muster (breit) | 473 / 443 (Common/Plugin) | 907 / 1 026 | Idiom; nur große n sind Befunde (P-08 erledigt für die Hotspots) |
| `with` | 0 | 0 | – |
| `Application.ProcessMessages` | 0 | 0 | – |
| leere `except` | 16 | 18 | alle kommentiert, gerechtfertigt |
| `Sleep(` | 8 | 13 | P-14 (neu `RunningPollMs`), P-16, Wächter-Test, Shutdown, HTTP-Polling, Vcs, QuickOpen |
| `TThread.Queue(nil` / `ForceQueue(nil` (Plugin) | 31 | 0 | A-02 erledigt |
| `TThread.Queue(Current` (Plugin) | – | 1 | T-02 (`Vcs.Worker`) |
| statische `TRegEx.Match/IsMatch` (Common) | 51 | 64 | P-11 |
| `{$WARN … OFF}` | 3 | 2 | mit `DEFAULT` |
| offene `TODO`/`FIXME`/`HACK` | 0 | 0 | alle Treffer beschreiben die TODO-Funktion |
| Polling-Timer im IDE-Layer | – | ≈ 29 | P-18 |

### 8.3 Geteilte Daten und Schutzmechanismen (Auswahl, Stand `c8f29bc1`)

| Daten | Geschrieben von | Gelesen von | Schutz | Befund |
|---|---|---|---|---|
| `TSymbolIndex.FFiles`, `FByName`, `FByAncestor` | Index-Thread, `EnsureUnit` (Pool) | alle Anfragen | `FLock` (`TCriticalSection`) | – |
| `TSymbolIndex.FUnitsSnapshot` | Index-Thread (nil setzen), erster Leser (aufbauen) | alle Anfragen, `NameIndex` | `FLock` beim Holen; danach **geteilt ohne Kopie** | **F-01** |
| `TStringPool` | `AddUnit` | – | `FPoolLock` | – |
| `TImportNameIndex` | gedrosselter Neuaufbau | Completion | `TMonitor`, unveränderlicher Snapshot | über F-01 betroffen |
| `FWorkspaces` (Shell) | Run-Thread (`AddWorkspace`/`RemoveWorkspace`) | Pool (`SettingsFor`, `PickWorkspace`, `NamingFor`) | `FWorkspacesLock` (`TMonitor`) | **T-01** (`NamingFor` ohne) |
| Namespaces der Features | Run-Thread (`ProjectLoaded`) | Pool | `Lsp.Internals.Namespaces` unter Sperre | A-03 erledigt |
| `FCompiling`, `FCompilerUnavailable` | Compile-Thread, Run-Thread | Run-Thread | `FCompileLock` | S-06 erledigt |
| `TLspPullDiagnostics`-Cache | Pool | Pool | `FCacheLock`, `TMonitor.Wait/PulseAll`, Interlocked | F-04 (Fehler nicht gemerkt) |
| `FSession`, `FServer`, `FStopping` (Plugin) | Hauptthread | Hauptthread, Zeitlimit-Arbeiter (`RunningSession`) | keine Sperre/Barriere | **T-03** |
| Hauptthread-Warteschlange (Plugin) | Arbeiter, Lese-Thread | Hauptthread | `TAtlasMainThread` mit Besitzer-Thread | A-02 erledigt; T-02 (`Vcs.Worker` vorbei) |
| `TAtlasIdeSettings.Current` | Hauptthread | Hauptthread (Malpfade) | Kopie je Aufruf | P-18 (Kosten, kein Rennen) |

### 8.4 Fremdabhängigkeiten

| Abhängigkeit | Verwendung | Lizenz/Status |
|---|---|---|
| Delphi-RTL, VCL, `vclwinx`, `designide` | Server, Plugin | Embarcadero, mit Delphi 12 |
| DUnitX | Testprojekt (`$(DUnitX)` im Suchpfad) | Apache 2.0 (`Tools/Licenses/Apache-2.0.txt`) |
| keine weiteren Laufzeitbibliotheken | – | `THIRD-PARTY-NOTICES.md`, `Tools/Check-NoEmbarcaderoSources.ps1` |

Eigener Parser statt DelphiAST (ADR 0001), eigener XML-Leser statt MSXML, eigener JSONC-Scanner – das Projekt hat bewusst keine Fremdbibliotheken zur Laufzeit.

### 8.5 Verstöße gegen die Importmatrix (18, alle als genehmigte Ausnahmen in `atlas.json`)

| Importierende Unit | importiert | Art |
|---|---|---|
| `Atlas.Common.Documents.Contract` | `Atlas.Text.Lines` | fremdes Root aus Contract |
| `Atlas.Common.Rules.Contract` | `Atlas.Common.Pascal.SyntaxTree` | fremdes Root aus Contract |
| `Atlas.IDE.CodeInsight.Composition` | 16 Units aus `Atlas.Core.*` (`Updates.Adapters.HttpSource`, `Ci.Providers.Jenkins`, `Ci.Adapters.Http`, `Ci.Adapters.Credentials`, `Tracker.Providers.GitHub`, `Tracker.Providers.YouTrack`, `Undo.Adapters.DiskTarget`, `Undo.Adapters.FileStore`, `Vcs.Composition`, `Vcs.Adapters.ProcessRunner`, `Lsp.Adapters.ServerProcess`, `Files.Adapters.FolderWatcher`, `Signature.Providers.Server`, `Completion.Providers.Server`, `Completion.Providers.Snippets`, `Completion.Providers.XmlDoc`) | fremde Providers/Adapters/Composition aus Composition (Host-Rolle, A-15) |

Die neun Root-Verstöße der IDE-Schicht vom 15.10. sind verschwunden – sie sind in die Kompositionswurzel gewandert. Inhaltlich ist das die richtige Stelle (Host-Shell), die Pauschalausnahme sollte aber auf Rollen beschränkt werden (A-15).

### 8.6 Nicht geprüft und warum

- **Atlas-MCP-Werkzeuge** (`get_diagnostics`, `get_last_build`, `check_code`): nicht erreichbar. Compiler-Warnungen und eigene Regelbefunde über den eigenen Code fehlen; die Codeskizzen in Abschnitt 5 sind nicht syntaxgeprüft.
- **Laufzeit und Absturz**: Kein Build, keine Ausführung. F-02/F-03/F-04 sind aus dem Code und der Übergabe-Notiz abgeleitet; welcher Auslöser den konkreten Vorfall verursacht, ist ohne Stack nicht bewiesen (5.1 Schritt 1 liefert die Datei).
- **Neue Refactorings im Detail**: `ChangeSignature`, `MoveClass`, `PropertyFromAccessors` nicht im Detail; `Extract` und `TIndenter` nur überflogen. Die Struktur wirkt vorsichtig (Planen vor Schreiben), Belastbares wurde nicht gefunden – das ist keine Freigabe.
- **Plugin-Bereiche ohne Lesung**: StartProfiles, Notes, Notifications, Bookmarks, Minimap nur über Notifier-/Timer-Zählung; Setup/Installer nur Struktur.
- **`Tests/`**: gezählt, nicht inhaltlich geprüft.
- **Generierter Code**: `Atlas.Core.Settings.PluginSchemaData`, `SchemaData`, `Rules.Catalog.Data` nicht gelesen (außer der Operatorzählung für F-03).
- **Werkzeuge dieses Reviews**: Skripte für Metriken, Importmatrix, Feature-Zyklen und Aufrufgraph im Scratchpad der Sitzung unter `/tmp/claude-0/-home-claude/8c584b58-9f83-52be-b907-36388650a51f/scratchpad/` (`metrics.py`, `check_roles.py`, `scc.py`, `cg.py`, `graph.py`). Im Repository wurde nichts geändert außer dieser Berichtsdatei.
