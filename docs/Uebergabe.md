# Übergabe: Atlas IDE Expert – Stand 09.10.2026

## Kontext
- Repo: https://github.com/xKnockOut/Atlas-IDE-Expert.git, lokal unter `C:\Projekte\BetterDelphiLSP\repo`. Gearbeitet wird auf `main`.
- Projektgruppe `Atlas.groupproj`: `Atlas.Common`, `Atlas.Windows` (Packages), `AtlasServer` (Anwendung), `Atlas.IDE.Expert` (Design-Time-Package, Win32, ADR 0006; bis #406 `Atlas.IdePlugin`), `Atlas.Tests` (DUnitX, nur Win64).
- Projektregeln in `CLAUDE.md`: Deutsch, UTF-8 mit BOM und CRLF, Rollenkonzept in `docs/Architektur.md`.
- Regeln des Users:
  - Hinweise und Warnungen sofort beheben. Ein Build gilt erst bei 0/0/0 als fertig.
  - Am Ende jedes Vorgangs diese Datei aktualisieren.
  - Vor öffentlichen Schritten auf GitHub (Kommentare, Issues) fragen.

## Wie hier gebaut wird
- RAD Studio 13 (37.0) ohne Kommandozeilen-Compiler. Gebaut wird über `C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1`, Doku liegt daneben.
- Pro Build eine frische IDE:
  1. `start -Project …\Atlas.groupproj -TimeoutSec 180`.
  2. Die pid aus der Zeile „IDE started : pid N“ ablesen. Die Ausgabe über alle Streams lesen (`*>&1`).
  3. Gegenprobe in `%LOCALAPPDATA%\ClaudeCompile\instances\<pid>\status.json`: Dort muss `Atlas.groupproj` stehen.
  4. `group-build -Instance <pid> -Platform Win64 -Json` ausführen.
  5. Tests mit `Output\Win64\Debug\Bin\Atlas.Tests.exe --exitbehavior:Continue` laufen lassen.
  6. `quit -Instance <pid>` so lange wiederholen, bis der Prozess beendet ist.
- Den ganzen Ablauf samt 0/0/0-Prüfung und Tests erledigt `pwsh Tools/Build-Test.ps1` (Optionen: `-Win32`, `-SkipTests`, `-CcScript`). Exit-Code 0 = grün, 1 = Build-Fehler/Hinweis/Warnung, 2 = Tests rot, 3 = Umgebungsfehler. Der CI-Job in `.github/workflows/server.yml` ruft dasselbe Skript auf.
- Das Referenz-Testprojekt (#94) baut `pwsh Tools/Build-Referenzprojekt.ps1` für Win32 und Win64 (`-MitDaten` zusätzlich das optionale FireDAC-Projekt `RefDaten`). Hinweise und Warnungen müssen genau `Tests/Referenzprojekt/erwartete-meldungen.txt` entsprechen; geänderte `.dproj`-Dateien lassen es scheitern. Die minimalen `.dproj`-Dateien einmal in der IDE speichern und einchecken.
- **Niemals `quit` oder einen Build ohne geprüfte `-Instance`.** Ein Agent für XML-Inspector nutzt dasselbe Plugin und lädt seine Projekte in freie IDEs. Erkennbar an einer veränderten `.groupproj`. Dann die Änderung verwerfen und mit neuer IDE wiederholen.
- **Fehlertexte nicht lesbar:** Das Plugin kann die Fehlertexte oft nicht lesen. Dann ist `ok=False` bei 0/0/0, im Log steht nur „Misslungen“. Die Ursache im Code suchen.
- **Häufige Fehlerursachen:**
  - Eine Funktion, die eine Methodenreferenz liefert, ohne `()` zugewiesen (E2010).
  - `TXyz.Create` direkt an einen `const`-Interface-Parameter übergeben.
  - Eine Methode steht zwischen Feldern (E2169).
  - Ein Typ im Interface-Teil stammt aus einer Unit, die nur in den uses des Implementation-Teils steht (E2003).
  - `GetValue<T>` direkt als Argument von `Assert`.
  - Doppeltes BOM in einer Datei.
  - `DUnitX.ServiceLocator` statt `DUnitX.IoC`.

## RAD Studio als LSP-Client (#175)
- **Anleitung:** `docs/RAD-Studio.md`. Wird mit #84 in `docs/Installation.md` verlinkt.
- **Eintrag in RAD Studio:**
  - Registry `HKCU\Software\Embarcadero\BDS\37.0\LSP\UserDefined\Atlas` mit `LanguageId = Delphi`.
  - Die IDE hält die Werte im Speicher und schreibt sie beim Beenden zurück. Änderungen deshalb im Dialog *Code Insight-Manager > Bearbeiten* machen, nicht in der Registry.
  - Die exe läuft direkt aus `repo\Output\Win64\Debug\Bin\` (Wunsch des Users). Vor jedem Build muss Delphi das Projekt geschlossen haben, sonst ist die exe gesperrt. Log und Mitschnitt liegen in `C:\Temp`.
  - `Help Insight` steht wieder auf `True`.
- **Funktioniert über den eingebauten Client:** Arbeitsbereich aus der Datei abgeleitet, documentSymbol, Diagnosen als Error Insight.
- **Hover funktioniert nicht und ist nicht lösbar über diesen Weg** (Belege in ADR 0006):
  - Ein Mitschnitt des eingebauten DelphiLSP zeigt dieselben Anfragen und die Antwort `{"contents":"…"}`, und die IDE zeigt sie an.
  - AtlasServer antwortet seit `ffed3c5` genauso.
  - Auch mit den Fähigkeiten von DelphiLSP und ohne Log- und Fortschrittsnachrichten (nur getestet, nicht committet) blitzt nur „Wird berechnet …“ auf.
- **Neustarts:** Kein Absturz. Jede `bds.exe` startet einen eigenen Server, außerdem gilt „Restart server each time a project is activated“. Die IDE startet zusätzlich parallel ihren eigenen DelphiLSP.
- **Behoben:** Ausweichen beim belegten `--trace` (`7d0cfaa`), Hover-Klartext als String (`ffed3c5`).
- **Entscheidung (ADR 0006):** Ein Design-Time-Package `Atlas.IdePlugin` (Win32) als Code Insight-Manager und dünner LSP-Client mit eigenem Serverprozess. Reihenfolge: Hover, Gehe zu Definition, Vervollständigung (#31), Parameterhilfe (#32), Error Insight selbst gezeichnet (`INTACodeEditorEvents`).
- **Werkzeuge der Analyse:**
  - Der Vermittler `LspProxy` liegt nur im Scratchpad, `C:\Temp\LspProxy` ist gelöscht.
  - In `bin` und `bin64` liegen noch je eine `DelphiLSP.proxy-alt.exe` (6 KB), die der User löschen kann (Administratorrechte nötig).
  - `DelphiLSP.exe` selbst ist wieder das Original.
- **Kommentar in #175** mit diesem Ergebnis ist veröffentlicht.

## IDE-Plugin `Atlas.IDE.Expert` (ADR 0006)
- **Stand (`c1cfae2`):** Code Insight-Manager „Atlas IDE Expert“ mit Hover (`GetHintText`) und Strg+Klick (`GotoDefinition`). Dünner LSP-Client (`Atlas.Core.Lsp.Client`, `.Session`, `.Adapters.ServerProcess`), 9 DUnitX-Tests in `Tests\IDE.Expert`, davon einer gegen den echten Server.
- **Projektgruppe:** Das Plugin steht seit diesem Vorgang in `Atlas.groupproj` (vom User in der IDE hinzugefügt). Ein `group-build -Platform Win64` erzeugt die BPL für die 64-Bit-IDE, Win32 die für die klassische IDE (ADR 0008, #281). Seit #281 heißt die BPL je IDE-Version `Atlas.IDE.Expert370.bpl` (Delphi 13) bzw. `…290.bpl` (Delphi 12); das alte `Atlas.IDE.Expert.bpl` einmal deinstallieren und die neue installieren. Win32 einzeln: `build -Project …\Packages\Atlas.IDE.Expert\Atlas.IDE.Expert.dproj -Platform Win32`.
- **Server:** Registry `HKCU\Software\Atlas\IdePlugin\ServerPath`, sonst neben der BPL, sonst `Output\Win64\Debug\Bin\AtlasServer.exe`. Solange das Plugin aktiv ist, ist diese exe gesperrt.
- **In der IDE getestet (User):** Hover funktioniert, Strg+Klick auf Bezeichner derselben Unit springt. Strg+Klick auf eine Klasse, die per `{$I …}` aus einer Include-Datei kommt, findet nichts: Auch mit #264 (Include-Resolver, jetzt in `main`) indiziert der Index keine Deklarationen aus `.inc`-Dateien. Dafür wäre ein eigenes Issue nötig (noch nicht angelegt, Entscheidung des Users offen); nachstellen mit einem eigenen kleinen Fixture im Repo.
- **Kein Zugriff auf Beryl:** Atlas-Arbeit greift nicht auf die Beryl-Quellen zu (keine Proben, Tests oder Issue-Begründungen damit). Automatisierte Abnahmen über Fixtures im Repo bzw. das Referenzprojekt #94; Beryl bleibt ein manueller Zusatztest des Users (#136, #138, #67, #72).
- **`ce3da00`:** Ohne Treffer gibt `GotoDefinition` `True` mit leerem Dateinamen und Zeile 0 zurück (mit `False` meldete die IDE „Datei "" nicht gefunden“). Diagnose: `Diagnose` = 1 (DWORD) unter `HKCU\Software\Atlas\IdePlugin` schreibt `Atlas.IDE.Expert.log` neben die BPL (Name folgt der BPL) (der Temp-Ordner funktionierte in der IDE des Users nicht).
- **Registry aus der Sandbox:** Werte für die IDE nur mit deaktivierter Sandbox schreiben, sonst sieht die vom User gestartete IDE sie womöglich nicht.
- **Delphi des Users** darf ich selbst schließen (`CloseMainWindow` auf `bds.exe`), wenn die Plugin-BPL oder die Server-exe gesperrt ist.
- **#406 (Package-Struktur):** Package heißt jetzt `Atlas.IDE.Expert` (Wunsch des Users), Units nach Schichten: `Atlas.Core.*` (`Source\Core`, ohne VCL und Open Tools API), `Atlas.UI.*` (`Source\UI`, nur VCL, noch leer), `Atlas.IDE.*` (`Source\IDE`, Open Tools API). `Tools/Check-PackageDependencies.ps1` prüft die Schichten und läuft jetzt auch unter Windows PowerShell 5.1 (`pwsh` fehlt hier). Der Registry-Schlüssel bleibt `HKCU\Software\Atlas\IdePlugin`.
- **Beim User nötig:** In der IDE das alte `Atlas.IdePlugin.bpl` entfernen und `Output\Win32\Debug\Bpl\Atlas.IDE.Expert.bpl` installieren.
- **#408 (Datenquelle):** `Atlas.Core.Completion.*`: `IAtlasCompletionProvider`/`IAtlasCompletionSink` (Teilmengen, genau ein `Complete`, nach `Cancel` nichts mehr), `TAtlasCompletionProviders` (Zusammenführen), `TAtlasServerCompletionProvider` (`Sync` im Hauptthread, `textDocument/completion` im Hintergrund; vor dem Freigeben der Sitzung `Shutdown`), `TAtlasFixedCompletionProvider` (Testdaten, optional verzögert). 7 Tests, davon einer gegen den echten Server. Entscheidung in ADR 0006 fortgeschrieben. Noch nicht im Manager verdrahtet (kommt mit dem Popup).
- **Popup (#410, #413, #414, #407, #429, #423, #416 Teil):** `Atlas.Core.Completion.Matching`/`Controller`, `Atlas.UI.Popup.Window`, `Atlas.UI.Completion.Popup`, `Atlas.IDE.Completion.Editor`, `Atlas.IDE.Editor.Buffer`. **In der IDE vom User getestet und funktionsfähig** (09.10.2026). Stand: Strg+Leer und `.` lösen aus; Filter nur gegen den Namen (den `filterText` des Servers für VS Code ignorieren!); Teilfolge nur an Wortgrenzen; Commit-Zeichen `(` `;` `.` bei klarem Treffer; leerer Zustand; Breite wächst nur. **Tasten:** keine IDE-Tastaturbindung für Pfeile/Enter/Tab/Pos1/Ende/Esc (nimmt sie dem Editor auch bei geschlossenem Popup weg), stattdessen Tastatur-Hook nur bei offenem Popup. Offene Frage zum Filtern: #497. Erledigt seither: Detailpanel (#424), Nachladen bei `isIncomplete` (#431), Parameter-Hint (#436), Aussehen (#411). Offen: Breite ziehen (#416), DPI und Zoom (#412, #445), Überladungen im Panel (#425), Tooltip bei gekürzten Einträgen (#420), Hover-Tooltip im Atlas-Stil (#442), verschachtelte Aufrufe (#438).
- **Parameter-Hint und Detailpanel (seit 09.10.2026):** Hint (#436, #437, #440) mit allen Überladungen untereinander (Wunsch des Users statt „‹ 1 / 3 ›“, also bewusst anders als der Entwurf), Detailpanel (#424, #426, #427) mit Daten aus `completionItem/resolve` (`data.atlas`). Überladungen nach Typen statt Anzahl: #498.
- **Atlas-Look nach den Entwürfen des Users (10.10.2026, #411, #420, #421, #439):** Die sieben Entwurfs-Artefakte des Users (claude.ai) geben das Aussehen vor: Akzent griechisches Blau `#0D5EAF` (dunkel `#5B9BE6`), Akzentrahmen, runde Ecken, Badges `fn pr pp fd ev co ty va un kw sn` in eigenen Farben, Treffer in Akzentfarbe, Detail rechtsbündig, Tags (`+ Unit`, deprecated, constructor), Fußzeile „Enter übernehmen · Esc schließen“ und „n von m“; Detailpanel als Teil des Popups (ein Rahmen mit Trennlinie wie im Entwurf, Hinweis des Users) auf abgesetzter Fläche mit eingefärbter Deklaration; Hint mit aktivem Parameter als Akzent-Pille, Doku-Zeile, Fehlerzustand „Keine Überladung mit n Parametern.“ (ohne „Meintest du“, das braucht #405). Neue Units `Atlas.Core.Style.Color/Palette/Syntax`, `Atlas.Core.Completion.Presentation`, `Atlas.UI.Popup.Styled`, `Atlas.IDE.Editor.Style`; 21 neue Tests (u. a. alle Farbrollen ≥ 4,5 : 1). Abweichungen vom Entwurf, weil der Kontrasttest sie verlangte: Auswahl dunkel 15 % statt 18 %, Typ-Badge dunkler als Funktions-Badge.
- **Übernahme mitten im Wort (`582975c`):** Ersetzt jetzt bis zum Wortende (`Atlas.Core.Completion.Word`), vorher blieb der Rest stehen (`TStringL|ist.` → `TStringListist.`). Beim Commit-Zeichen endet das Wort weiterhin davor.
- **Hint nach entfernter Klammer (Wunsch des Users):** Wird die schließende Klammer gelöscht (Rücktaste/Entf) und steht der Caret danach in einem Aufruf, öffnet der Parameter-Hint erneut (`TAtlasCallScanner.RemovedClosingParen`, Vergleich mit der Zeile vor der Änderung in `EditorModified`). Nicht für einen Aufruf, dessen Hint mit Esc geschlossen wurde. `ConcurrentWritersLeaveReadableCache` meldete dabei in 2 von 3 Läufen wieder 104 Byte (zeitabhängig, unverändert offen).
- **Serie Vervollständigungs-Issues (10.10.2026, Auftrag des Users: alle nacheinander, am Ende Prüfliste):** Erledigt und committet: #438, #412/#445, #420/#441/#409, #227 (Plugin-Teil)/#407/#413, #428/#416, #419/#422/#418, #425, #446, #435, #430; dazu Server-Daten in `data` (container, depth, helper, overloads, parameters) und der Leck-Fix in `ConcurrentWritersLeaveReadableCache` (RTL-Ressourcentext von EFileNotFoundException, jetzt in der Aufwärmphase). Prüfliste nach Issues: `docs/Atlas-Testfaelle.md` (noch nicht committet, wächst mit).
  - **Unterbrochen (User: „Stop, wir machen später weiter“) mitten in #442 Hover-Tooltip:** Uncommittet und ungebaut: `Atlas.Common.Lsp.Hover.pas` gibt in der Hover-Antwort zusätzlich `atlas` (declaration, unit, documentation, value, deprecation) über `TLspHover.AtlasJson` aus, Test `AtlasPartsForTooltip`. Geplant: `TLspSession.HoverParts`, Fenster `Atlas.UI.Hover.Tip`, Editor-Anbindung über `ToolsAPI.Editor` (`TNTACodeEditorNotifier`, `OnEditorMouseMove`, `EditorState.PointToCharacterPos`, `LineState[...].LogicalLineNum`), 500 ms Öffnen, 300 ms Schließen, `GetHintText` liefert bei aktivem Schalter ''.
  - **Danach offen:** #434 Vorschau (Zeichnen über `ToolsAPI.Editor` PaintText/PaintLine), #414/#432 prüfen, #443, #444, #417 (braucht Typen), #447, dann Auswahl ab #448.
  - **Hilfsskripte (Scratchpad):** `cycle.ps1` (normalisieren, Schichten, Bau ohne Delphi-Neustart, Tests), `add-units.ps1` (Units in dpk/dproj/Tests), `demo-build.ps1` + `demo\AtlasPopupDemo.dpr` (Fotos der Fenster). Nach `cycle.ps1` ist Delphi des Users zu: wieder starten.
  - **Stolperstein erneut:** Typografische Anführungszeichen („ “ ‘ ’) in PowerShell-Strings beenden den String still; Pascal-Code mit solchen Zeichen nur mit dem Edit-Werkzeug ändern.
- **Fallstricke Fensteraussehen:** (1) Unter Windows 11 rundet DWM die Ecken (`DWMWA_WINDOW_CORNER_PREFERENCE`) und zeichnet den Rahmen (`DWMWA_BORDER_COLOR`); die Fensterregion für ältere Windows darf erst nach dieser Entscheidung gesetzt werden, sonst setzt `Resize` während `inherited CreateWnd` eine leere Region, und das Fenster bleibt bis auf den DWM-Rahmen unsichtbar, und `Paint` wird nie aufgerufen. (2) Zum Prüfen ohne IDE: Demo `scratchpad\demo\AtlasPopupDemo.dpr` (Units per `in`-Pfad), bauen mit `demo-build.ps1` (Community-Edition: kein `dcc32` auf der Kommandozeile), Foto per `BitBlt` mit `CAPTUREBLT`.
- **Plugin aktuell halten (Wunsch des Users):** Nach jeder Plugin-/Serveränderung `update-plugin.ps1` (Scratchpad): Delphi des Users schließen, Gruppe Win64 und Plugin Win32 bauen, Delphi neu starten. Bricht ab, wenn Delphi einen Dialog offen hat.
- **Fokus (User, 09.10.2026):** nur Delphi/RAD Studio; VS Code und andere Editoren später.
- **Plan Vervollständigung (User-Entscheidung: direkt eigenes Popup):** #406 → #408 Provider-Interface → #405 Teil 1 (Server-Daten) → #410 Popup ohne Fokus, #413 virtuelle Liste, #414 Schließlogik, Tastenweiterleitung (#399), #407 eingebaute Completion unterdrücken → #409 lokales Filtern; danach #395, Rest #393, #493.
- **Offen:** Parameterhilfe (`GetParameterList`), Error Insight selbst gezeichnet.

## Feature-Kette (abgeschlossen am 09.10.2026)
- 98 verkettete Branches von `14-projektmodell` bis `122-binaere-dfm`.
- **Stand:** vollständig in `main` (letzter Schritt Index 97 `122-binaere-dfm`), 964 Tests. Übersprungen wurden nur die „nicht geplanten“ Issues (siehe unten).
- **Abhängigkeiten zu übersprungenen Branches, so gelöst:**
  - #254 ohne #179 (siehe unten); `completeBlocks` aus #179 ist auch aus Schema, `Konfiguration.md`, `Einstellungen.md` und VS-Code-`package.json` entfernt (#307, #265). `Tools/Update-ConfigDoc.ps1` braucht `pwsh` (hier nicht installiert); die erzeugten Dateien wurden von Hand angepasst, bei Gelegenheit mit `pwsh Tools/Update-ConfigDoc.ps1 -Check` gegenprüfen.
  - #113 nutzte `TFormEvents.EventTail` aus #111: Die Funktion steht jetzt in `TPublishedMembers.EventTail` (mit Test), `FormEvents` entfällt.
  - #122 baute auf #115 und #111 auf: Übernommen sind nur der Befehl `atlas.server.convertBinaryForms` und die Code-Aktion „Formular in Text umwandeln“; dafür kam der Hook `TLspCodeActions.FormActions` aus #115 mit. Vererbungsaktion, `FormEvents.CreateCommand` und `FileOperations` (#181) fehlen bewusst.
  - `unit-name-mismatch` (#86) fehlt in allen Profil-Erwartungen; `Builtin.UnitFiles` und `FileOperations` fehlen in `Architektur.md`.
- **Leck-Monitor (Ursache der Meldungen im vollen Lauf, Branch `claude/project-thread-ppmemb`, Nachweis in der IDE offen):** Der Monitor misst prozessweit und sah Arbeit anderer Threads. Ursachen per Codeanalyse: (1) Die RTL hält Warteobjekte von `TMonitor` (Wait, `TLightweightEvent`, Thread-Pool) in einem Zwischenspeicher, dessen Verwaltungsknoten (24 Byte unter Win64) bis Programmende bleiben; er wächst in dem Thread, der gerade fertig wird, oft ein Pool- oder Überwachungs-Thread früherer Tests mitten in einem fremden Test (`DeepNestingIsReportedNotFatal` hat selbst keine Threads). (2) Threads des Tests geben ihren letzten Speicher erst kurz nach dem Signal frei (Lese-Thread nach `ReaderDone`, Task nach dem Ende). (3) Negative Salden wertete DUnitX ebenfalls als Leck. Behoben in `Atlas.Tests.LeakMonitor`: `PrewarmRuntime` (viele Threads gleichzeitig in `TMonitor.Wait`, Standard-Thread-Pool, `TThread.CurrentThread`), Nachwarten bis 250 ms bei positivem Rest, negativer Saldo = 0, Bericht mit Thread-Anzahl (`IMemoryLeakMonitor2`). `[IgnoreMemoryLeaks]` an `DeepNestingIsReportedNotFatal` entfernt. Nachweis: 10 volle Läufe ohne Leck-Meldung.
- **Vor jedem Branch Issue prüfen (Auftrag des Users):** offen → übernehmen; geschlossen → prüfen, ob noch gebraucht. Laut Durchsicht vom 09.10.2026 (Epic #392) „nicht geplant“ und aus der Kette genommen: #86 (Index 61), #179 (65), #181 (67), #111 (94), #115 (96). `review-befunde` (68) hat kein Issue, enthält Review-Korrekturen und wird übernommen.
- **Seit #460 (Umbenennung) neues Verfahren, Skript `chainrun2.ps1` im Scratchpad:** Eigene Änderung des Branches (Basis = `merge-base` mit dem Vorgänger in der Kette, so fallen ausgelassene Branches heraus) auf beiden Ständen mit `rename-atlas.ps1` umbenennen (gegen #460 geprüft) und als 3-Wege-Cherry-Pick auf `main` anwenden (Arbeitsbranch `kette-arbeit`), bauen, testen, per Fast-Forward nach `main`. Die Feature-Branches auf GitHub bleiben unverändert (kein Force-Push). Listenkonflikte in `.dpr`/`.dpk`/`.dproj` (`resolve-lists.ps1`) und reine H2443-Hinweise (`fix-h2443.ps1`) löst das Skript selbst.
- **#254 ohne #179:** `/uses` hing im onTypeFormatting-Handler aus #179. Übernommen ohne Blockabschluss (User-Entscheidung): Handler nur für `/uses`, Capability `documentOnTypeFormattingProvider`, Einstellung `usesCommand`. Achtung bei späteren Branches, die auf `completeBlocks`/`BlockCompletion` aufbauen.
- **Behoben in 55–66:** H2443 (mehrfach), Zeilentransport-Tests (Lecks, `ä`), Index-Cache-Flags ohne `GetValue<Boolean>` (Leck), E1019 in `Completion.AddFromOtherUnits`, Konflikte in VS-Code-`package.json`, `Architektur.md` (`atlas.server.status` wie im Code), Editor-Dateien `betterdelphilsp` → `atlas`, `bench.mjs` mit `AtlasServer.exe`.
- **Behoben in 41–54:** Merge-Konflikte (Hover-Klartext mit Wert/Deprecation, Shell.Composition mit Compiler und abgeleiteten Arbeitsbereichen, Shell.Workspace-uses, mehrfach `Atlas.Tests.dpr`), `Count`/`Length` als `Integer` (E2532), `ReadTabsConfig()` (E2010), H2077, H2443, DFM-Gliederungstest.
- **Kettenskript:** Löst selbst: Listenkonflikte, falsche `;` in `.dpr`/`.dpk`-Listen nach konfliktfreiem Merge (`fix-terminators.ps1`), Profiltest-Erwartungen (Branch-Seite ohne `unit-name-mismatch`), `Architektur.md` und `Konfiguration.md` (Branch-Seite ohne Teile übersprungener Branches), H2443 und E2532. Jeder andere Konflikt hält an.
- **Leck-Monitor (seit 177):**
  - Felder im `TearDown` freigeben.
  - Einmal-Belegungen der RTL im `[SetupFixture]` vorab auslösen; `[IgnoreMemoryLeaks]` nur mit Begründung.
  - Bei reinen Leck-Fehlschlägen bis zu sechs Läufe; gilt als zeitabhängig, wenn jeder gemeldete Test mindestens einmal sauber war.
- **Weitere Fixes in 78–97:** E2029 (Listentrenner), Profilerwartungen (#269, #91, #124, #125), Konflikte `UsesClause` (#284), `Shell.Composition` (#283: Mitschnitt rotiert und weicht aus; Methodendeklaration hinter die Felder), `DiskFileSystem` (#62: `EArgumentException` und `EOSError`), `System.Classes` im Index-Test, RotatingFileStream-Tests (`WillRaiseDescendant`).
- Die IDE sortiert `DCCReference` um und fügt Leerzeilen ein. Reine Umsortierungen und Leerraum-Änderungen werden verworfen.

## Umbenennung in Atlas (#403, 09.10.2026)
- **GitHub:** Das Repository heißt jetzt `xKnockOut/Atlas-IDE-Expert` (vom User umbenannt, alte URLs leiten weiter). Der lokale Ordner `C:\Projekte\BetterDelphiLSP\repo` bleibt, bis der User ihn selbst umbenennt.
- **Code:** Präfix `Atlas.*` statt `BDLsp.*` in Units, Ordnern, `.dpk`, `.dproj`; Projektgruppe `Atlas.groupproj`; Anwendung `Application\AtlasServer.dpr` → `AtlasServer.exe`; Tests `Tests\Atlas.Tests.dpr` → `Atlas.Tests.exe`; Plugin `Atlas.IdePlugin.bpl`, Typ `TAtlasCodeInsightManager`.
- **Namen nach außen:** Code Insight-Manager „Atlas IDE Expert“, `serverInfo.name`, `source` der Diagnosen und SARIF-Werkzeug „Atlas“. Befehle des Servers `atlas.server.compile`, `atlas.server.selectBuild`, `atlas.server.status`; Editor-Abschnitt `atlas` (VS Code `atlas.*`); Cache `%LOCALAPPDATA%\Atlas`, Compiler-Ausgabe `%TEMP%\Atlas\dcc-…`.
- **Abwärtskompatibel:** `atlas.json` und `atlas-baseline.json`; fehlen sie, gelten `delphi-lsp.json` bzw. `delphi-lsp-baseline.json` (`ExistingOrLegacyFile`, `IsConfigurationFileName`). Das Plugin liest `HKCU\Software\Atlas\IdePlugin`, ersatzweise den alten Schlüssel `HKCU\Software\BetterDelphiLSP\IdePlugin`; zeigt dessen `ServerPath` auf eine fehlende exe, gelten die Vorgaben.
- **Beim User nach dem ersten Bau nötig:**
  - Altes Package `BDLsp.IdePlugin.bpl` in der IDE entfernen, `Output\Win32\Debug\Bpl\Atlas.IDE.Expert.bpl` installieren, im Code Insight-Manager „Atlas IDE Expert“ wählen.
  - Der benutzerdefinierte LSP-Eintrag `UserDefined\BetterDelphiLSP` zeigt noch auf `BetterDelphiLSP.exe`: im Dialog auf `AtlasServer.exe` umstellen (Name `Atlas`).
  - Alte Ausgaben (`BetterDelphiLSP.exe`, `BDLsp.*.bpl/.dcp`, `%LOCALAPPDATA%\BetterDelphiLSP`) können gelöscht werden.
- **Feature-Kette:** Beim Einmergen von `main` in die übrigen Branches folgen Umbenennungen von Dateien meist automatisch. Neue Units der Branches und ihre uses-Einträge danach nach denselben Regeln umbenennen: `BDLsp` → `Atlas`, `bdlsp` → `atlas`, `BetterDelphiLSP` → `AtlasServer` in `.dproj`/`.groupproj`/`.dpr`, sonst `Atlas`; `delphi-lsp.json` → `atlas.json`. Danach muss `git grep -n "BDLsp\|BetterDelphiLSP"` leer sein, außer an den Stellen für Abwärtskompatibilität.
- **Offen:** Gruppenbau und Tests in der IDE (in der Cloud nicht baubar). Schichten `Atlas.Core/UI/IDE` und eigenes `Atlas.Tests.dpr` für das Plugin folgen mit #406 und #415.

## Aufräumen der Branches (10.10.2026)
- `main` auf GitHub = `d21b4d2`: Atlas-Vervollständigungsserie, #500, #527, #501, #536, #502, #514, #528, #548, #556, #99, #48 und der Merge von `claude/project-thread-ppmemb` (Leck-Monitor). Gruppe 0/0/0, 1111 Tests ohne Lecks.
- **Gelöscht** (Sicherung aller Stände mit Commit in `C:\Projekte\BetterDelphiLSP\branch-sicherung-2026-10-10.txt`): 124 vollständig gemergte Branches (65 remote, 59 lokal), die Doku-Branches `claude/project-thread-1qlm6n`, `-pjsmb5`, `-mhrxdt`, der gemergte `-ppmemb`, 38 Ketten-Branches mit Inhalt per Squash in `main` und 7 mit geschlossenem Issue (#86, #111, #115, #179, #181, #271, #308).
- **Übrig: 48 Ketten-Branches** (Index 98 ff. hinter `122-binaere-dfm`), alle mit offenem Issue und Code, der nicht in `main` ist; noch mit Namen vor der Umbenennung. Reihenfolge der Kette: 123 → 126 → 149 → 151 → 261 → 270 → 281 → 282 → 293 … 299 → 304 → 309 → 319 → 152 → 56 → 128 → 120 → 313 → 312 → 187 → 153 → 153-typen → 277 → 278 → 157 → 188 → 276 → 300 → 303-ausdruck → 301 → 302 → 306 → 320 … 323 → 303-modern → 119 → 88 → 89 → 104 → 114 → 87. Nachbauen mit dem Verfahren aus `chainrun2.ps1` (Umbenennen, 3-Wege-Cherry-Pick, Listenkonflikte selbst lösen), Branch nach Übernahme löschen. Achtung: #261 überschneidet sich mit #527/#528/#548, #188 mit der umgebauten Vervollständigung.
- **Issues:** 77 umgesetzte geschlossen (mit Commit im Kommentar). Bewusst offen: #48 (Abnahme mit Claude Code), #62 und #100 (nur teilweise), #102 (Teil 1), #227 (nur Vervollständigung), #99 (schreibende Werkzeuge), #414 (Hint schließt beim Scrollen statt mitzuwandern), #433, #447, #528/#548 (Error Insight, projektweite Liste), #536 (Sammeldialog, Vergleichen).
- Testfälle der umgesetzten Plugin-Issues: `docs/Atlas-Testfaelle.md`.

## Nachbau der Ketten-Branches (Stand 10.10.2026, 18:20, angehalten)
- **Verfahren:** Skript `C:\Projekte\BetterDelphiLSP\kette\chainrun3.ps1` (Liste `chain3.txt` daneben: Branch|Vorgänger|Basis-Commit). Je Branch nur dessen eigene Commits umbenennen und als 3-Wege-Cherry-Pick auf `kette-arbeit` anwenden, bauen (eigene IDE, Win64-Gruppe), testen, per Fast-Forward nach lokalem `main`. Gepusht wird in Blöcken von 5–10 Branches; danach Abnahme der Issues prüfen (schließen mit Commit im Kommentar oder Stand kommentieren) und die Branches auf GitHub löschen. Fortsetzen mit `chainrun3.ps1 -StartAt <Index> -StopAfter <Index> [-ResumeLocal]`.
- **Das Skript löst selbst:** Listenkonflikte, H2443, einfache E2532, Leck-Wiederholungen, Doku-Einfügungen (`doc_inserts.py`) und neue Regeln im Profiltest (`fixprof.py`: Kategorie aus `regelkatalog.json`, experimentelle Regeln über `Merged(All, [...])` im strict-Fall). Alles andere hält an.
- **Gepusht und Branches gelöscht:** Blöcke 1–4, Index 98–129: #123, #126 (ohne Vererbung), #149, #151, #270, #281, #282, #293–#299, #304, #319, #152, #56, #128, #120, #313, #312, #187, #153 (beide Stufen), #277, #278, #157, dazu der Cache-Fix #62 (`6dcce739`). origin/main = `3d85d18f`.
- **Lokal auf `main`, nicht gepusht (Block 5):** #276, #300, #303 (Ausdrucksbefehle), #301, #302, #306, #320, #321 – alle grün.
- **Lokal auf `kette-arbeit`, Build abgebrochen:** #322 (`0a1084bf`) mit drei Korrekturen (`Inline` → `UseInline`; Umschließen lehnt reine Leerzeilen ab, in `CommandSource.Wrap` und `TaskCommands.FollowingLines`; Test `/parallel` mit `ShowMessage`). Weiter mit `-StartAt 39 -StopAfter 39 -ResumeLocal`, danach Block 5 pushen, Abnahme von #276, #300, #301, #302, #303, #306, #320–#322 prüfen, Branches löschen.
- **Danach offen in der Kette (Index 40–47):** #323, #303-modern, #119, #88 (`DocComments.pas` enthält `Exit([Action])`, unter dcc64 E2001 → als `Result := [...]; Exit;` schreiben), #89, #104, #114, #87.
- **Übersprungen, nach der Kette neu bauen (User-Entscheidung):**
  - #309 Eigenschaftsregeln: neu auf `Atlas.Common.Dfm.FormModel` (#267), Einstellung `dfmPropertyRules` und Tests aus dem Branch, kein Code aus dem abgelehnten #308.
  - #188 Postfix-Vorlagen: Server-Teil aus dem Branch übernehmen und das Plugin erweitern (textEdit-Bereich ersetzen, filterText bei Postfix-Einträgen, Snippets als Klartext; Tests in Core).
  - #261 ganz übersprungen; Branch bleibt auf GitHub.
- **Fallstricke der Branches (aus Cloud-Sitzungen, nie unter Delphi gebaut):**
  - `Exit([..])` → E2001 unter dcc64.
  - Reservierte Wörter als Bezeichner, z. B. `Inline`.
  - Methodendeklaration zwischen Feldern → E2169.
  - Testhelfer mit `/` statt `\` (`ExtractFileName` trennt unter Windows nicht an `/`).
  - Falsch gezählte Hochkommas in Literalen.
  - Widersprüchliche Testerwartungen.
  - Leck-Meldungen im ersten Test einer Fixture → `[SetupFixture]` zum Aufwärmen.
  - Direkte Aufrufe von `TPascalParser.Parse` → über `TSyntaxTreeCache.Parse` (Wächter #262).
  - `TDUnitX.CurrentRunner.Log` zählt als Leck → `System.Writeln`.
- **Teile abgelehnter Issues weglassen:** #111 (FormEvents, FormItems), #115 (TFormActionsFunc des Branches), #179 (Blockabschluss), #308 (FormSymbols), #309 (DfmPropertyRules in #312).
- **Offen zu entscheiden (im Issue kommentiert):** #157 filtert die Dateien vor der Prüfung statt nur die Ausgabe.
- **CI:** „Package-Abhängigkeiten“ ist seit `64e42a6a` wieder grün (`package.json` im Format von `Update-ConfigDoc`). `pwsh` fehlt lokal; `Tools/Check-Delphi12.ps1` und den package.json-Teil von `Update-ConfigDoc.ps1` gibt es als Python-Nachbau (`check_d12.py`, `configpkg.py`) in `C:\Projekte\BetterDelphiLSP\kette`.
- **Delphi des Users:** wurde von einer Nebensitzung über `cycle.ps1` geschlossen; am 11.10.2026 mit dem neuen Plugin wieder gestartet.

## Stand 11.10.2026: Kette abgeschlossen, #588 umgesetzt
- **Kette:** alle Ketten-Branches nachgebaut, gepusht und gelöscht. Übrig: `feature/261-ide-compiler` (übersprungen), `feature/309-eigenschaftsregeln` und `feature/188-postfix-vorlagen` (Vorlagen für die Neubauten). Abnahmen je Block geprüft; teilweise erfüllte Issues sind kommentiert und offen.
- **Nebenbefunde:**
  - Referenzzyklus in `TLspHover.InfoAt` behoben (lokale anonyme Methode `ReadText`, 752 Byte je Klassen-Hover).
  - `Rules.Catalog.Data.pas` mit `Tools/Update-RuleCatalog.ps1` neu erzeugt; die CI war seit dem Kettennachbau rot.
  - Unter PowerShell 5.1 das Skript als UTF-8 laden, sonst werden die Umlaute verfälscht: `powershell -Command "& ([scriptblock]::Create([IO.File]::ReadAllText('Tools\Update-RuleCatalog.ps1', [Text.Encoding]::UTF8))) -Root C:\Projekte\BetterDelphiLSP\repo"`.
- **#588 Hover-Tooltip-Navigation:**
  - Server `68a55b05`: `Atlas.Common.Lsp.HoverTypes`; Hover und Referenzen lesen nicht geöffnete Dateien selbst.
  - Plugin `39723c99`: `Atlas.Core.Hover.Contract/History`, Tooltip mit Pfadzeile, Links, Kette und Aktionsleiste.
  - Aussehen an den Entwurf (Artifact „Atlas Tooltip-Navigation“) angeglichen (`3f571121`): Randflächen für Pfad, Kette und Aktionsleiste, Kettenglieder als Kästchen, Verweise in Akzentfarbe, Pfad höchstens vier Einträge.
  - Die manuelle Abnahme HN1–HN9 in `docs/Atlas-Testfaelle.md` steht aus; das Issue ist offen.
- **Bauen:**
  - `C:\Projekte\BetterDelphiLSP\kette\build.ps1` baut die Gruppe (Win64) und die Tests in einer eigenen IDE; es sichert `.dproj`/`.dpk` vorher und schreibt sie danach zurück.
  - Plugin für den User: `kette\update-plugin.ps1`, ohne Sandbox ausführen. Es startet Delphi nur neu, wenn es vorher lief.
- **#309 Eigenschaftsregeln (`b2039f6d`):**
  - Neu auf `FormModel`: Einstellung `dfmPropertyRules` und Regel `dfm-property`.
  - Meldung in der Unit; nicht gespeicherte Properties gelten mit ihrem `default` aus der Klasse.
  - Offen: Korrekturen in der DFM, Projektbefehl, Diagnose bei unbekannter Klasse.
  - Der Branch `feature/309-eigenschaftsregeln` bleibt als Vorlage stehen.
- **#188 Postfix-Vorlagen (Server `9f6d527c`, Plugin `6bba6ffb`):**
  - Das Plugin ersetzt bei Einträgen mit `textEdit` ab dessen Anfang.
  - Offen: Platzhalter-Modus (#51) und die manuelle Prüfung PF1–PF6.
- **Farbfehler im Editor behoben (`d93a834f`):** Klammerfarben (#514) und Vorschau (#434) ließen ihre Textfarbe im DC stehen; beim Neuzeichnen einzelner Bereiche wurden Teile von Bezeichnern in Paarfarbe gezeichnet. Jetzt direkt im DC zwischen SaveDC/RestoreDC.
- **Klammerfarben, zweiter Teil (`f8125482`):** Die IDE meldet beim Neuzeichnen von Teilbereichen nicht immer die Zeile des Laufs. Eingefärbt wird nur, wenn der Lauf an seiner Spalte in der analysierten Zeile steht (`TAtlasPairs.DisplayLine/RunMatches`).
- **Blocklinien (`e8e021d0`):** Atlas zeichnet Blocklinien in den Paarfarben (`Atlas.Core.Editor.Guides`, PaintLine in `Atlas.IDE.Editor.Pairs`) und schaltet die Strukturhervorhebung der IDE per Registry ab (`Atlas.IDE.Editor.Structure`, Merker `IdeStructureDisabled` unter `HKCU\Software\Atlas\IdePlugin`). Die IDE schreibt den Schalter beim Beenden nicht zurück (geprüft). Testfälle KP9–KP13.
- **Probleme im Editor (#398, offene Teile von #528/#548):**
  - Plugin holt Diagnosen per Pull (`TLspSession.DocumentDiagnostics/WorkspaceDiagnostics`, Capabilities `textDocument.diagnostic` und `workspace.diagnostics.refreshSupport`; der Server pusht dann nicht mehr). `TLspClient.OnServerMessage` zählt `workspace/diagnostic/refresh` (`TLspSession.RefreshCount`).
  - `Atlas.Core.Problems.Contract/Store` (Markierungen wandern mit, dcc bis zum nächsten Compile blass), `Atlas.IDE.Problems.Controller` (Timer 250 ms, Dokument-Thread, Workspace-Thread mit Long-Polling, didClose für geschlossene Dateien; Manager.StopSession hält die Threads an und schließt vorher die Verbindung), `Painter` (Wellenlinien), `MessageList` (Gruppe „Atlas-Probleme“).
  - Hover-Tooltip zeigt Probleme oben, auch ohne Bezeichner. Einstellung `Problems` (Standard an).
  - `9d2e9459`: Compilermeldungen ohne Pfad (die IDE nennt teils nur `Gallery.Main.pas`) ergänzt das Plugin zu vollen Pfaden (`TAtlasCompilerMessages.Resolve`). Vom User abgenommen; #398, #528, #548 geschlossen.
  - Das Plugin startet den Server jetzt selbst und sofort neu: Für Builds Delphi des Users schließen (`update-plugin.ps1 -NoRestart`, dann `build.ps1`, dann Delphi starten).
- **Delphi 12 (#281, 11.10.2026):** Tastatur-Ereignisse des Editors nur ab Delphi 13 (`e4ea3519`); Senden an den Server in eigenem Thread mit 1-MB-Pipe gegen Einfrieren (`98058471`); Hänger beim Laden großer Projekte lagen laut Wächter in der IDE selbst. Auf dem Delphi-12-Rechner fehlte `AtlasServer.exe`: jetzt Einstellung „Atlas-Server“ in den Optionen, und ohne Server bleibt die Code Insight der IDE aktiv (`ad3920bb`).
- **Help Insight (`2a678103`):** Solange der Atlas-Tooltip an ist, schaltet Atlas Help Insight der IDE ab (Registry `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`, `Help Insight`, Merker `IdeHelpInsightDisabled`); unter Delphi 12 zeigte die IDE sonst beide Tooltips. Auf diesem Rechner geprüft (Wert False, Merker 1).
- **Achtung:** Das Plugin war gegen 12:26 aus „Known Packages“ verschwunden (Ursache unklar); der User hat es neu installiert.
- **Plugin beim User:** am 11.10.2026 um 12:38 aktualisiert.
- **Achtung:** In `Atlas.Common.Compiler.OutputParser.pas` stehen Testzeilen des Users (verschachtelte begin/end); nicht committen.
- **Neu in `update-plugin.ps1`:** sichert `.dproj`/`.dpk` vor dem Bau und schreibt sie danach zurück.
- **Weiter:**
  - Reste der Serie: #528/#548, #536, #414, #443, #433, #447, #227, #99, #48, #102.
  - Danach weitere Issues nach Priorität.

## Stand 11.10.2026 (Nachtrag)

- MCP: explain_finding, rename_symbol, apply_code_action; CheckOnSave über die IDE standardmäßig aus, Plugin schickt didSave, Server prüft mit dcc (54bf7479).
- Regel `unresolved-identifier` (fc636997).
- #536: Sammeldialog entfernt, Unterschied im Meldungsfenster (ea0b4a25, geschlossen).
- #414: Hint/Popup schließen bei Größenänderung, Hint wandert beim Scrollen mit, Tooltip schließt bei Fokus-/Tabwechsel (3d6a38b8); Abnahme SL1–SL9 offen.
- #443 war schon erledigt (450ac5b7).
- #433: Einstellung „Schreibweise beim Übernehmen korrigieren“ (b853a445); Abnahme offen.
- #447: UI-Automation + Ansagen für Popup, Hint, Tooltip (e5208869); Abnahme mit Narrator offen.
- Hinweis: neue .pas ohne BOM lassen den Test NoParserCallsOutsideCache 40 Byte „lecken“ (TEncoding-Instanz) – immer mit BOM speichern.
- Weiter: #227, #102.
- Fix Übernahme: Server-Add leerte Scored nicht (leeres textEdit löschte bis Dateianfang, 4924a925); Importe mit Klammern (895d6177).
- #227: Dialog Atlas > Projekt-Einstellungen (atlas.json aus Schema, kommentarerhaltend), Hauptmenü Atlas mit Schnellschaltern (ba3a8208, 7fa02c4a).
- #493: TAtlasGuard + Sicherung je Feature, Protokoll %LOCALAPPDATA%\Atlas\Logs (a42a03a6); offen: 200-ms-Limit, Entladen.
- #492: Fortschritt im Menütitel, Index-Status/Neuaufbau (ef1b32d6); Tipp-Pause-Index (04bbde94, a92bd2f6, 0f14d324) vom User bestätigt; offen: geteilter Bibliotheks-Index, #470, #476.
- Fehlersuche: Registry HKCU\Software\Atlas\IdePlugin ServerArguments="--log <datei> --log-level debug" und Diagnose=1 (danach wieder entfernen).


## #616 Vervollständigung zu langsam (12.10.2026, Branch `feature/616-completion-langsam`)

- **Ursache (Codeanalyse, nicht gemessen):** Der Server meldete im unscharfen Modus immer `isIncomplete`. Bei jedem Tastendruck schickte das Plugin daher den vollen Text, und der Server baute für alle sichtbaren Symbole (alle uses-Units) vollständige Records, sortierte und kürzte erst dann auf 1000. Dazu kam ein quadratisches Einlesen im Plugin.
- **Server:**
  - `TNameResolver.NameFilter` baut nur passende Namen auf; `OwnScopeCandidates`/`UsedScopeCandidates` teilen ScopeCandidates.
  - `isIncomplete` nur noch bei Kürzung, gekappten Importen oder einem Präfix unter 2 Zeichen.
  - Mit `partialResultToken` kommen Teilergebnisse als `$/progress`: eigene Unit, dann uses; die Antwort bringt die Importe. Zwischen den Stufen wird ein Abbruch geprüft.
  - Zeiten je Anfrage gehen ins Debug-Protokoll (`completion: …`).
  - `completionItem/resolve` puffert die zuletzt gelesene, nicht geöffnete Datei.
- **Plugin:**
  - `TLspClient.Request` mit `AOnPartial`; `Fetch` hat `AEmit`.
  - `TAtlasCompletionController.NeedsQuery`: neu fragen nur, wenn die Liste gekürzt ist oder das Wort nicht mehr mit dem Präfix der Anfrage beginnt.
  - Einlesen und Rangfolge ohne Anhängen je Eintrag.
  - Popup misst die Breite bei Pfeiltasten nicht neu.
  - Gruppen zum erwarteten Typ nur, wenn ein Eintrag passt.
- **Offen:**
  - Nicht gebaut und nicht getestet (Cloud).
  - „0 aus dem Cache“ behoben (`Cleanup` schützt beide Cache-Dateien); beim User bestätigt: 1239 aus dem Cache, Lauf noch 63 s, 351 gelesen.
- **#617 Umsetzungsreihenfolge** (Marco: Punkte 5, 7, 4 zuerst; alle Schritte in #617):
  - Includes: `TUnitIndex.IncludeStamps` (Cache-Format 9, Schlüssel `its`). Units mit Includes kommen aus dem Cache, solange alle Include-Dateien denselben Zeitstempel haben.
  - Sperre: `TIndexService` schützt nur noch den Zugriff auf den Builder und zählt Nutzer (`AcquireBuilder`/`ReleaseBuilder`/`ReplaceBuilder`); `EnsureUnit` parst ohne Sperre. `ApplyText`/`ApplyChanges` laufen über `FApplyLock` in Reihe. Der neue Builder wird erst nach `UseCache` veröffentlicht.
  - Namensindex: `Atlas.Common.Index.NameIndex` (`TImportNameIndex`, `TImportNames.Current`) mit Zeichenmaske je Name; `ISymbolIndex.Generation` meldet Änderungen. `AddFromOtherUnits` nutzt ihn. Große Schnappschüsse werden während des Aufbaus höchstens einmal pro Sekunde erneuert.
  - Nicht gebaut und nicht getestet (Cloud). Neue Tests: `CachedIncludeUnitReusedUntilIncludeChanges`, `EnsureUnitDoesNotWaitForOtherRequests`, `TImportNameIndexTests`.
  - Cache-Format 10: Zeilen mit Tabulator-Feldern statt JSON (`TIndexCache`, Kopf `ATLAS-INDEX`), ein Durchlauf ohne JSON-Baum. Der erste Start danach liest alles neu. Dateiname bleibt `index-*.json`.
  - Punkt 9 (dauerhafter Server) verworfen (Marco). Punkt 2 (Bibliothek je Version) besteht weitgehend seit #492.


## Critical-Issues (14.10.2026, Branch `claude/critical-issues-ygbl9i` von main)

- Offen mit priority:critical: #616, #617, #647, #648. Alle bleiben offen: nicht in main, nicht gebaut, nicht gemessen.
- **#617 Schritt 4, Binärformat** (6e373cb): Cache-Format 11 (Magie `ATLASIDX`) mit String-Tabelle und Varints; `TIndexCache.ReadEntries` liest nur die Köpfe, `Expand` dekodiert die Symbole einer Unit erst, wenn der Builder sie übernimmt. Dazu kommen `IIndexFileSystem.ReadBytes`/`WriteBytes`. FPC-Messung mit synthetischen Daten (1569 Units, 575.823 Symbole): Schreiben 990 ms, 16 MB; Köpfe 3 ms; alles dekodieren 399 ms. Die Reihenfolge „eigenes Projekt zuerst, Bibliothek danach im Hintergrund“ besteht schon: `Build` erst die Projektdateien, dann `IndexReferenced`, alles im Index-Thread. Offen: Messung bei Marco.
- **#647 Diagnoselog** (9d9aaca):
  - Common: `Atlas.Common.Diagnostics.Contract`, `Anonymizer` (Kurz-IDs, Filter, `StackFrame`), `RequestScope` (threadvar, Grundcodes), `Providers.Log` (Puffer bis `Configure`), `Adapters.LogFolder` (`diag-JJJJMMTT-<pid>.log`, Laufmarken `run-<pid>.open`).
  - Windows: `Atlas.Windows.Diagnostics.ProcessInfo`.
  - Dispatcher: `IJsonRpcRequestObserver`.
  - Server: `Shell.Diagnostics`. Es schreibt nach %LOCALAPPDATA%\Atlas\Logs\Diagnose; der Endgrund kommt aus `OnExit`, dem Wächter des Elternprozesses oder einer Exception.
  - Einstellungen: `diagnostics` als Objekt mit `log`, `logDays`, `logMapFile`. Das Issue nennt `diagnostics.log.days`; das geht nicht, weil `log` schon der Schalter ist.
  - Plugin: `Atlas.Core.Diagnostics.Export`, `Atlas.UI.Diagnostics.ExportDialog`, `Atlas.IDE.Diagnostics.Export`; Menü Atlas und Palette „Diagnoselog exportieren…“.
  - Tests: `Atlas.Common.Diagnostics.Tests`, `Shell.Diagnostics.Tests` (Markertest über Log, Vorschau und ZIP).
  - Weil der Filter „/“ verwirft, steht im Log „line N of M“ statt „N/M“, und die LSP-Methodennamen sind freigegeben (`AllowMethods`).
  - Offen: Delphi-Build mit 0/0/0, Testlauf, Test in der IDE. Ein PR ist noch nicht angelegt (öffentlicher Schritt, erst nach Rückfrage).
- **#648 Projektgruppe, Suchpfade, Bibliothek** (neu angelegt auf Marcos Wunsch; #619 als darin aufgegangen geschlossen, die vier Schalter in #227 eingetragen, beides nach Marcos Zustimmung):
  - Einstellungen `index.projectGroup`, `index.searchPaths`, `index.libraryPaths` (Vorgabe an) und `index.exclude` (Glob gegen den vollen Pfad), Seite „Speicher“.
  - Common: `Atlas.Common.Projects.GroupReader` (Projekte einer `.groupproj`), `Atlas.Common.Index.Scheduler` (ein Aufbau zur Zeit; erst alle Projektdateien, dann Suchpfade, dann Bibliothek; aktives Projekt zuerst), `TIndexProjectFiles.PathFiles`, `TIndexBuilder.Build` mit drei Listen und `IIndexTurn`. Suchpfad-Units zählen zum Projekt, Bibliotheks-Units als Bibliothek.
  - `TWorkspaceFolder.ProjectFile` und `Key`: Ein workspaceFolders-Eintrag darf eine `.dproj` oder `.groupproj` sein.
  - Server: je Projekt ein Arbeitsbereich mit fester Projektdatei (`AddProjectWorkspace`), `Origin` zum Entfernen, `WorkspaceOf` zuerst über `ContainsFile`. Mit `index.projectGroup = false` warten die übrigen Projekte, bis eine ihrer Dateien geöffnet wird (`Activate`). Meldet der Client nur Projektdateien, werden Arbeitsbereiche für fremde Dateien weiter abgeleitet.
  - Plugin: `TLspSession.SetProjects` schickt die Projekte der `MainProjectGroup` (aktives zuerst) in `initialize` und später als `didChangeWorkspaceFolders`; der Manager prüft die Gruppe höchstens alle 2 s im Hauptthread.
  - Tests: GroupReader, PathFiles, Scheduler, Build-Stufen, workspaceFolders mit Projektdateien, ProjectChanges.
  - Offen: Delphi-Build mit 0/0/0, Testlauf, Messung mit einer echten Gruppe (Zeit und Speicher, wenn die ganze Bibliothek indiziert wird).

## Diagnoselogs vom 14.10.2026 (#647, Branch `claude/diag-log-fixes-s1pg9d`)

- **Befund:** Zwei Logs von Marco. Lauf 1 (ein Projekt): workspace/diagnostic prüfte während des Indexaufbaus alle Projektdateien mit je ~300 ms (Budget 3 s je Anfrage, dann sofort die nächste) und meldete fehlende Units. Lauf 2 (Projektgruppe, 2000 Units): Hover 100–500 s, workspace/diagnostic bis 116 s, executeCommand bis 79 s, Warteschlange bis 22 s; der Lauf davor endete ohne Endzeile.
- **Ursachen (Codeanalyse, nicht gemessen):**
  - `TServerComposition.EnsureUnit` hielt `FWorkspacesLock`, während jeder Arbeitsbereich die Unit suchte und parste. An derselben Sperre hängen Defines, Einstellungen, Regelkontext und `IndexLoading` des Diagnoselogs je Anfrage: Alles lief hintereinander.
  - `TNameResolver.FindUnit` lud erst nach (Suchpfade aller Projekte) und prüfte die Namespace-Schreibweise im Index erst danach; Fehlschläge wurden je Aufruf wiederholt. `ResolveFirst` prüfte für jedes Präfix von `A.B.C`, ob es eine Unit ist, mit Nachladen.
  - Workspace-Diagnosen liefen während des Aufbaus; ihre Ergebnis-Ids änderten sich danach nicht, die falschen Befunde blieben stehen.
  - Das Plugin beendet den Server 2 s nach dem Schließen von stdin; der Server wartete bis 5 s auf laufende Anfragen und schrieb die Endzeile erst danach.
- **Fixes:** EnsureUnit außerhalb der Sperre (Nutzerzähler je Arbeitsbereich, `RemoveWorkspace` wartet), Index zuerst und Fehlschläge je Resolver merken, Präfixe nur für Units aus uses nachladen (`FindQualifierUnit`), `TLspPullDiagnostics.Busy` (wartet während des Aufbaus, Grundcode `indexLoading`, sonst `noChanges`), `OnIndexFinished` → `Refresh`, Long-Polling 10 s, Endzeile über `TJsonRpcConnection.OnLoopEnded` (EndRun zählt nur einmal). Nebenbei: `StartIndex` gab den alten `TUnitResolver` frei, den der alte Builder bis zum Veröffentlichen des neuen noch über EnsureUnit aufruft (Zugriff auf freigegebenen Speicher, mögliche Absturzursache); jetzt in `FRetiredResolvers` bis zum Ende des Arbeitsbereichs.
- **Offen:** Delphi-Build mit 0/0/0, Testlauf, neue Logs von Marco. Nicht angefasst: `workspace/executeCommand` läuft weiter in der Nachrichtenschleife (Neuaufbau wartet dort auf den alten Index-Thread); welche Units wirklich fehlen, zeigt das anonymisierte Log nicht.
- **Runde 2 (Log 5604, nach PR #650):** Hover schnell (≤ 1 s). Aber workspace/diagnostic meldete den ganzen Lauf über `indexLoading`, textDocument/diagnostic brauchte 8–26 s und lief nach jeder Indexmeldung erneut, references lief in Zeitlimits. Vermutung (nicht gemessen, das normale Log war ohne `--log` leer): Der Aufbau einer Projektgruppe endet erst nach allen Projekten samt Bibliothek, der Cache wurde erst dann geschrieben; ein früheres Schließen der IDE ließ alles neu parsen.
- **Fixes Runde 2:** `TIndexBuilder.Build` ruft `AProjectDone` nach der Projektstufe; `TIndexService` schreibt dort schon den Cache (`WriteCaches`) und meldet `OnProjectReady`. `TShellWorkspace.ProjectPending` steuert jetzt `TLspPullDiagnostics.Busy` (statt `IndexLoading`). `TLspSyntaxDiagnostics.RefreshLater` bündelt die Neuprüfung (2 s). Diagnoselog: `index project#N start …`, `projectStage …`, `done …` (Dateien, ms, parsed, cached, missing).
- **Offen Runde 2:** Build 0/0/0 und Tests bei Marco; neues Log zeigt, ob die Bibliothek aus dem Cache kommt (`cached` in den `index`-Zeilen). Langsame Regeln einzelner großer Dateien sind nicht untersucht.
- **Runde 3 (Index-Zeilen aus Marcos Server-Log, Projektgruppe mit 8 Projekten, ~2000 Units):** Ein voller Aufbau dauert 7,5–16 min; die Projekte laufen nacheinander (Stufe Projekt), je 40–190 s, auch mit `neu=0` aus dem Cache (63 ms je Unit) oder nur ~120 neu gelesenen Units. Suchpfad- und Bibliotheksstufe sind leer (`suchpfad=0 bibliothek=0`), alles läuft über uses. Cache-Treffer fehlen nach Neustarts teils ganz (`cache=0`), vermutlich nach einem neuen Server-Build (nicht geprüft).
- **Fixes Runde 3:** `IndexReferenced` liest eine über einen anderen Namen gefundene Datei (`Forms` → Vcl.Forms) nicht neu, wenn sie mit gleichem Zeitstempel im gemeinsamen Index steht. `TIndexBuildResult.ResolveMs/ParseMs` gehen in die Zeile `index project#N done`. Server-Log anonym über `TLogAnonymizer` (Atlas.Common.Diagnostics.Anonymizer) und `TTransformLogSink`; Namen meldet `TShellWorkspace.OnNames`, Units aus dem Index `IndexFinished`; `--log-names` schaltet ab. Kommandozeile nimmt `-log`/`–log`.
- **Offen Runde 3:** Woher die übrigen ~60 ms je Unit kommen (Suche über die Bibliothekspfade? Virenscanner?), zeigen erst `resolve`/`parse` im nächsten Diagnoselog.
- **Runde 4 (Diagnoselog, eine 53-KB-Datei mit 1439 Zeilen, Index 2024 Units):** Jede Anfrage auf diese Datei braucht 10–107 s ohne Wartezeit in der Warteschlange: Hover 9,6 s (`noTarget`) bis 107 s (`missingUnits=1`), Vervollständigung 51–73 s und damit `timeout` (das Plugin wartet 2 s, daher das leere Fenster „Keine Vorschläge“).
- **Vermutete Ursachen (Codeanalyse, nicht gemessen):** `TSymbolIndex.Locations` (FindSymbols, Descendants) lief über alle Symbole aller Units unter `FLock` und kopierte dabei jeden Symbol-Record zweimal; Prüfregeln rufen das je Feld/Typ auf, und FindUnit/FindFile jeder anderen Anfrage warteten auf dieselbe Sperre. Fehlende Units: `TNameResolver.FindUnit` rief EnsureUnit zusätzlich für jeden Namespace auf, obwohl `TUnitResolver` die Namespaces schon selbst probiert (je Namespace ein voller Suchlauf über alle Ordner).
- **Fixes Runde 4:** Locations auf Schnappschuss (`Units`) ohne Sperre, Zugriff über Index, Filter mit `const`-Parameter (`TIndexSymbolFilter`), FindSymbols prüft zuerst die Länge. `ShrinkLocked` kehrt sofort zurück, wenn das Budget reicht oder alles kompakt ist. EnsureUnit nur noch für den Namen selbst. Diagnoselog: `cpu=` (GetThreadTimes), `parallel=` (gleichzeitig laufende Anfragen, Kurznamen ohne „/“), `treeMs=` (Hover, Vervollständigung), `ensureMs=` (NameResolver).
- **Bibliothek einmalig (Frage von Marco):** `LibrarySignature` ohne Projekt-Defines (`LIBRARY2|Plattform|Version`); Units unter dem BDS-Ordner liest der Builder mit `LibraryDefines` (nur Compiler-Symbole, `TIndexBuilder.LibraryRoots`). Nur der BDS-Ordner, nicht der ganze Bibliothekspfad: eigener Code dort wird oft mit dem Projekt übersetzt. Über uses erreichte Units außerhalb der Installation gehen in den Projekt-Cache. `index.libraryPaths` (alle Bibliotheks-Units statt nur der über uses erreichten) steht weiter in atlas.json; das Plugin gibt dem Server keine globalen Einstellungen weiter.
- **#652 (Marco: „Global“):** `TAtlasPluginSettings.IndexProjectGroup/IndexSearchPaths/IndexLibraryPaths` (HKCU), drei Kästchen auf der Optionsseite, `ServerSettingsJson` geht als `initializationOptions.settings.atlas` (`TLspSession.ServerSettings`) und bei `TAtlasIdeSettings.OnChanged` als didChangeConfiguration an den Server. Server: `OnInitialized` setzt `FEditorSettings` aus `initializationOptions` vor `AddWorkspace`.
- **Offen Runde 4:** Das nächste Diagnoselog entscheidet: `cpu` nahe `ms` heißt Rechnen (dann Profil der Anfrage nötig), `cpu` weit darunter heißt Warten (Sperre oder Datei-Suche, siehe `ensureMs`/`treeMs`).
- **Runde 5 (Problemliste von Marco zu Atlas selbst):** fast nur Fehlalarme eigener Regeln. Signatur: `ParameterKey` normalisiert jetzt je Parameter (`NormalizedParameters`, `SplitTopLevel`), ohne Standardwerte. Nicht deklariert: `TNameResolver.IsBuiltinTypeName`, `IsUnitPrefix` (erst nach erfolglosem ResolveChain, weil der FCurrent setzt), `MethodClasses` löst `TAussen.TInnen` über FindMember auf; Intrinsics um Atomic*, MaxInt, MaxLongint, HInstance ergänzt (MaxInt: Ursache nicht geprüft, eigentlich steht es in System). result-not-set: `TFlowBuilder.BuildTry` baut das finally je Ausgang einmal (normal, je Sprungziel; Ausnahmewege zuletzt, damit `NodeOf` den normalen Weg findet). Folgen: `UnreachableStatements` meldet eine Anweisung nur, wenn keine Kopie erreichbar ist, und nur einmal; `unused-assignment` prüft alle Kopien. `possibly-uninitialized` nutzt weiter `NodeOf`, also im finally den normalen Weg.
- **Offen Runde 5:** Build und Tests bei Marco. Nicht untersucht aus der Liste: unused-assignment, security-insecure-http, format-without-settings, empty-except, possibly-uninitialized, ifthen-side-effect, float-equality. Verschachtelte try/finally vervielfachen die Knoten (je Ebene Faktor Ausgänge + 1).
