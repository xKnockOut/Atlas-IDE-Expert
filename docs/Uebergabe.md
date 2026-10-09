# Übergabe: Argus IDE Expert – Stand 09.10.2026

## Kontext
- Repo: https://github.com/xKnockOut/Argus-IDE-Expert.git, lokal unter `C:\Projekte\BetterDelphiLSP\repo`. Gearbeitet wird auf `main`.
- Projektgruppe `Argus.groupproj`: `Argus.Common`, `Argus.Windows` (Packages), `ArgusServer` (Anwendung), `Argus.IDE.Expert` (Design-Time-Package, Win32, ADR 0006; bis #406 `Argus.IdePlugin`), `Argus.Tests` (DUnitX, nur Win64).
- Projektregeln in `CLAUDE.md`: Deutsch, UTF-8 mit BOM und CRLF, Rollenkonzept in `docs/Architektur.md`.
- Regeln des Users:
  - Hinweise und Warnungen sofort beheben. Ein Build gilt erst bei 0/0/0 als fertig.
  - Am Ende jedes Vorgangs diese Datei aktualisieren.
  - Vor öffentlichen Schritten auf GitHub (Kommentare, Issues) fragen.

## Wie hier gebaut wird
- RAD Studio 13 (37.0) ohne Kommandozeilen-Compiler. Gebaut wird über `C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1`, Doku liegt daneben.
- Pro Build eine frische IDE:
  1. `start -Project …\Argus.groupproj -TimeoutSec 180`.
  2. Die pid aus der Zeile „IDE started : pid N“ ablesen. Die Ausgabe über alle Streams lesen (`*>&1`).
  3. Gegenprobe in `%LOCALAPPDATA%\ClaudeCompile\instances\<pid>\status.json`: Dort muss `Argus.groupproj` stehen.
  4. `group-build -Instance <pid> -Platform Win64 -Json` ausführen.
  5. Tests mit `Output\Win64\Debug\Bin\Argus.Tests.exe --exitbehavior:Continue` laufen lassen.
  6. `quit -Instance <pid>` so lange wiederholen, bis der Prozess beendet ist.
- Den ganzen Ablauf samt 0/0/0-Prüfung und Tests erledigt `pwsh Tools/Build-Test.ps1` (Optionen: `-Win32`, `-SkipTests`, `-CcScript`). Exit-Code 0 = grün, 1 = Build-Fehler/Hinweis/Warnung, 2 = Tests rot, 3 = Umgebungsfehler. Der CI-Job in `.github/workflows/server.yml` ruft dasselbe Skript auf.
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
  - Registry `HKCU\Software\Embarcadero\BDS\37.0\LSP\UserDefined\Argus` mit `LanguageId = Delphi`.
  - Die IDE hält die Werte im Speicher und schreibt sie beim Beenden zurück. Änderungen deshalb im Dialog *Code Insight-Manager > Bearbeiten* machen, nicht in der Registry.
  - Die exe läuft direkt aus `repo\Output\Win64\Debug\Bin\` (Wunsch des Users). Vor jedem Build muss Delphi das Projekt geschlossen haben, sonst ist die exe gesperrt. Log und Mitschnitt liegen in `C:\Temp`.
  - `Help Insight` steht wieder auf `True`.
- **Funktioniert über den eingebauten Client:** Arbeitsbereich aus der Datei abgeleitet, documentSymbol, Diagnosen als Error Insight.
- **Hover funktioniert nicht und ist nicht lösbar über diesen Weg** (Belege in ADR 0006):
  - Ein Mitschnitt des eingebauten DelphiLSP zeigt dieselben Anfragen und die Antwort `{"contents":"…"}`, und die IDE zeigt sie an.
  - ArgusServer antwortet seit `ffed3c5` genauso.
  - Auch mit den Fähigkeiten von DelphiLSP und ohne Log- und Fortschrittsnachrichten (nur getestet, nicht committet) blitzt nur „Wird berechnet …“ auf.
- **Neustarts:** Kein Absturz. Jede `bds.exe` startet einen eigenen Server, außerdem gilt „Restart server each time a project is activated“. Die IDE startet zusätzlich parallel ihren eigenen DelphiLSP.
- **Behoben:** Ausweichen beim belegten `--trace` (`7d0cfaa`), Hover-Klartext als String (`ffed3c5`).
- **Entscheidung (ADR 0006):** Ein Design-Time-Package `Argus.IdePlugin` (Win32) als Code Insight-Manager und dünner LSP-Client mit eigenem Serverprozess. Reihenfolge: Hover, Gehe zu Definition, Vervollständigung (#31), Parameterhilfe (#32), Error Insight selbst gezeichnet (`INTACodeEditorEvents`).
- **Werkzeuge der Analyse:**
  - Der Vermittler `LspProxy` liegt nur im Scratchpad, `C:\Temp\LspProxy` ist gelöscht.
  - In `bin` und `bin64` liegen noch je eine `DelphiLSP.proxy-alt.exe` (6 KB), die der User löschen kann (Administratorrechte nötig).
  - `DelphiLSP.exe` selbst ist wieder das Original.
- **Kommentar in #175** mit diesem Ergebnis ist veröffentlicht.

## IDE-Plugin `Argus.IDE.Expert` (ADR 0006)
- **Stand (`c1cfae2`):** Code Insight-Manager „Argus IDE Expert“ mit Hover (`GetHintText`) und Strg+Klick (`GotoDefinition`). Dünner LSP-Client (`Argus.Core.Lsp.Client`, `.Session`, `.Adapters.ServerProcess`), 9 DUnitX-Tests in `Tests\IDE.Expert`, davon einer gegen den echten Server.
- **Projektgruppe:** Das Plugin steht seit diesem Vorgang in `Argus.groupproj` (vom User in der IDE hinzugefügt). Ein `group-build -Platform Win64` übersetzt es mit (0/0/0), installiert wird aber die Win32-BPL `Output\Win32\Debug\Bpl\Argus.IDE.Expert.bpl`. Win32 einzeln: `build -Project …\Packages\Argus.IDE.Expert\Argus.IDE.Expert.dproj -Platform Win32`.
- **Server:** Registry `HKCU\Software\Argus\IdePlugin\ServerPath`, sonst neben der BPL, sonst `Output\Win64\Debug\Bin\ArgusServer.exe`. Solange das Plugin aktiv ist, ist diese exe gesperrt.
- **In der IDE getestet (User):** Hover funktioniert, Strg+Klick auf Bezeichner derselben Unit springt. Strg+Klick auf eine Klasse, die per `{$I …}` aus einer Include-Datei kommt, findet nichts: Auch mit #264 (Include-Resolver, jetzt in `main`) indiziert der Index keine Deklarationen aus `.inc`-Dateien. Dafür wäre ein eigenes Issue nötig (noch nicht angelegt, Entscheidung des Users offen); nachstellen mit einem eigenen kleinen Fixture im Repo.
- **Kein Zugriff auf Beryl:** Argus-Arbeit greift nicht auf die Beryl-Quellen zu (keine Proben, Tests oder Issue-Begründungen damit). Automatisierte Abnahmen über Fixtures im Repo bzw. das Referenzprojekt #94; Beryl bleibt ein manueller Zusatztest des Users (#136, #138, #67, #72).
- **`ce3da00`:** Ohne Treffer gibt `GotoDefinition` `True` mit leerem Dateinamen und Zeile 0 zurück (mit `False` meldete die IDE „Datei "" nicht gefunden“). Diagnose: `Diagnose` = 1 (DWORD) unter `HKCU\Software\Argus\IdePlugin` schreibt `Argus.IDE.Expert.log` neben die BPL (Name folgt der BPL) (der Temp-Ordner funktionierte in der IDE des Users nicht).
- **Registry aus der Sandbox:** Werte für die IDE nur mit deaktivierter Sandbox schreiben, sonst sieht die vom User gestartete IDE sie womöglich nicht.
- **Delphi des Users** darf ich selbst schließen (`CloseMainWindow` auf `bds.exe`), wenn die Plugin-BPL oder die Server-exe gesperrt ist.
- **#406 (Package-Struktur):** Package heißt jetzt `Argus.IDE.Expert` (Wunsch des Users), Units nach Schichten: `Argus.Core.*` (`Source\Core`, ohne VCL und Open Tools API), `Argus.UI.*` (`Source\UI`, nur VCL, noch leer), `Argus.IDE.*` (`Source\IDE`, Open Tools API). `Tools/Check-PackageDependencies.ps1` prüft die Schichten und läuft jetzt auch unter Windows PowerShell 5.1 (`pwsh` fehlt hier). Der Registry-Schlüssel bleibt `HKCU\Software\Argus\IdePlugin`.
- **Beim User nötig:** In der IDE das alte `Argus.IdePlugin.bpl` entfernen und `Output\Win32\Debug\Bpl\Argus.IDE.Expert.bpl` installieren.
- **#408 (Datenquelle):** `Argus.Core.Completion.*`: `IArgusCompletionProvider`/`IArgusCompletionSink` (Teilmengen, genau ein `Complete`, nach `Cancel` nichts mehr), `TArgusCompletionProviders` (Zusammenführen), `TArgusServerCompletionProvider` (`Sync` im Hauptthread, `textDocument/completion` im Hintergrund; vor dem Freigeben der Sitzung `Shutdown`), `TArgusFixedCompletionProvider` (Testdaten, optional verzögert). 7 Tests, davon einer gegen den echten Server. Entscheidung in ADR 0006 fortgeschrieben. Noch nicht im Manager verdrahtet (kommt mit dem Popup).
- **Popup (#410, #413, #414, #407, #429, #423, #416 Teil):** `Argus.Core.Completion.Matching`/`Controller`, `Argus.UI.Popup.Window`, `Argus.UI.Completion.Popup`, `Argus.IDE.Completion.Editor`, `Argus.IDE.Editor.Buffer`. **In der IDE vom User getestet und funktionsfähig** (09.10.2026). Stand: Strg+Leer und `.` lösen aus; Filter nur gegen den Namen (den `filterText` des Servers für VS Code ignorieren!); Teilfolge nur an Wortgrenzen; Commit-Zeichen `(` `;` `.` bei klarem Treffer; leerer Zustand; Breite wächst nur. **Tasten:** keine IDE-Tastaturbindung für Pfeile/Enter/Tab/Pos1/Ende/Esc (nimmt sie dem Editor auch bei geschlossenem Popup weg), stattdessen Tastatur-Hook nur bei offenem Popup. Offene Frage zum Filtern: #497. Erledigt seither: Detailpanel (#424), Nachladen bei `isIncomplete` (#431), Parameter-Hint (#436), Aussehen (#411). Offen: Breite ziehen (#416), DPI und Zoom (#412, #445), Überladungen im Panel (#425), Tooltip bei gekürzten Einträgen (#420), Hover-Tooltip im Argus-Stil (#442), verschachtelte Aufrufe (#438).
- **Parameter-Hint und Detailpanel (seit 09.10.2026):** Hint (#436, #437, #440) mit allen Überladungen untereinander (Wunsch des Users statt „‹ 1 / 3 ›“, also bewusst anders als der Entwurf), Detailpanel (#424, #426, #427) mit Daten aus `completionItem/resolve` (`data.argus`). Überladungen nach Typen statt Anzahl: #498.
- **Argus-Look nach den Entwürfen des Users (10.10.2026, #411, #420, #421, #439):** Die sieben Entwurfs-Artefakte des Users (claude.ai) geben das Aussehen vor: Akzent griechisches Blau `#0D5EAF` (dunkel `#5B9BE6`), Akzentrahmen, runde Ecken, Badges `fn pr pp fd ev co ty va un kw sn` in eigenen Farben, Treffer in Akzentfarbe, Detail rechtsbündig, Tags (`+ Unit`, deprecated, constructor), Fußzeile „Enter übernehmen · Esc schließen“ und „n von m“; Detailpanel als Teil des Popups (ein Rahmen mit Trennlinie wie im Entwurf, Hinweis des Users) auf abgesetzter Fläche mit eingefärbter Deklaration; Hint mit aktivem Parameter als Akzent-Pille, Doku-Zeile, Fehlerzustand „Keine Überladung mit n Parametern.“ (ohne „Meintest du“, das braucht #405). Neue Units `Argus.Core.Style.Color/Palette/Syntax`, `Argus.Core.Completion.Presentation`, `Argus.UI.Popup.Styled`, `Argus.IDE.Editor.Style`; 21 neue Tests (u. a. alle Farbrollen ≥ 4,5 : 1). Abweichungen vom Entwurf, weil der Kontrasttest sie verlangte: Auswahl dunkel 15 % statt 18 %, Typ-Badge dunkler als Funktions-Badge.
- **Übernahme mitten im Wort (`582975c`):** Ersetzt jetzt bis zum Wortende (`Argus.Core.Completion.Word`), vorher blieb der Rest stehen (`TStringL|ist.` → `TStringListist.`). Beim Commit-Zeichen endet das Wort weiterhin davor.
- **Hint nach entfernter Klammer (Wunsch des Users):** Wird die schließende Klammer gelöscht (Rücktaste/Entf) und steht der Caret danach in einem Aufruf, öffnet der Parameter-Hint erneut (`TArgusCallScanner.RemovedClosingParen`, Vergleich mit der Zeile vor der Änderung in `EditorModified`). Nicht für einen Aufruf, dessen Hint mit Esc geschlossen wurde. `ConcurrentWritersLeaveReadableCache` meldete dabei in 2 von 3 Läufen wieder 104 Byte (zeitabhängig, unverändert offen).
- **Fallstricke Fensteraussehen:** (1) Unter Windows 11 rundet DWM die Ecken (`DWMWA_WINDOW_CORNER_PREFERENCE`) und zeichnet den Rahmen (`DWMWA_BORDER_COLOR`); die Fensterregion für ältere Windows darf erst nach dieser Entscheidung gesetzt werden, sonst setzt `Resize` während `inherited CreateWnd` eine leere Region, und das Fenster bleibt bis auf den DWM-Rahmen unsichtbar, und `Paint` wird nie aufgerufen. (2) Zum Prüfen ohne IDE: Demo `scratchpad\demo\ArgusPopupDemo.dpr` (Units per `in`-Pfad), bauen mit `demo-build.ps1` (Community-Edition: kein `dcc32` auf der Kommandozeile), Foto per `BitBlt` mit `CAPTUREBLT`.
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
  - #122 baute auf #115 und #111 auf: Übernommen sind nur der Befehl `argus.server.convertBinaryForms` und die Code-Aktion „Formular in Text umwandeln“; dafür kam der Hook `TLspCodeActions.FormActions` aus #115 mit. Vererbungsaktion, `FormEvents.CreateCommand` und `FileOperations` (#181) fehlen bewusst.
  - `unit-name-mismatch` (#86) fehlt in allen Profil-Erwartungen; `Builtin.UnitFiles` und `FileOperations` fehlen in `Architektur.md`.
- **Leck-Monitor, offen:** `DeepNestingIsReportedNotFatal` ist vorläufig mit `[IgnoreMemoryLeaks]` markiert (im vollen Lauf 24–40 Byte, allein sauber, Ursache unbekannt). `ConcurrentWritersLeaveReadableCache` meldet gelegentlich ein Leck. Einmal-Belegungen der RTL (erste `EFOpenError`, Kodierungen) werden per `[SetupFixture]` vorab ausgelöst. Für die Ursachensuche ist eine eigene Aufgabe vorgeschlagen.
- **Vor jedem Branch Issue prüfen (Auftrag des Users):** offen → übernehmen; geschlossen → prüfen, ob noch gebraucht. Laut Durchsicht vom 09.10.2026 (Epic #392) „nicht geplant“ und aus der Kette genommen: #86 (Index 61), #179 (65), #181 (67), #111 (94), #115 (96). `review-befunde` (68) hat kein Issue, enthält Review-Korrekturen und wird übernommen.
- **Seit #460 (Umbenennung) neues Verfahren, Skript `chainrun2.ps1` im Scratchpad:** Eigene Änderung des Branches (Basis = `merge-base` mit dem Vorgänger in der Kette, so fallen ausgelassene Branches heraus) auf beiden Ständen mit `rename-argus.ps1` umbenennen (gegen #460 geprüft) und als 3-Wege-Cherry-Pick auf `main` anwenden (Arbeitsbranch `kette-arbeit`), bauen, testen, per Fast-Forward nach `main`. Die Feature-Branches auf GitHub bleiben unverändert (kein Force-Push). Listenkonflikte in `.dpr`/`.dpk`/`.dproj` (`resolve-lists.ps1`) und reine H2443-Hinweise (`fix-h2443.ps1`) löst das Skript selbst.
- **#254 ohne #179:** `/uses` hing im onTypeFormatting-Handler aus #179. Übernommen ohne Blockabschluss (User-Entscheidung): Handler nur für `/uses`, Capability `documentOnTypeFormattingProvider`, Einstellung `usesCommand`. Achtung bei späteren Branches, die auf `completeBlocks`/`BlockCompletion` aufbauen.
- **Behoben in 55–66:** H2443 (mehrfach), Zeilentransport-Tests (Lecks, `ä`), Index-Cache-Flags ohne `GetValue<Boolean>` (Leck), E1019 in `Completion.AddFromOtherUnits`, Konflikte in VS-Code-`package.json`, `Architektur.md` (`argus.server.status` wie im Code), Editor-Dateien `betterdelphilsp` → `argus`, `bench.mjs` mit `ArgusServer.exe`.
- **Behoben in 41–54:** Merge-Konflikte (Hover-Klartext mit Wert/Deprecation, Shell.Composition mit Compiler und abgeleiteten Arbeitsbereichen, Shell.Workspace-uses, mehrfach `Argus.Tests.dpr`), `Count`/`Length` als `Integer` (E2532), `ReadTabsConfig()` (E2010), H2077, H2443, DFM-Gliederungstest.
- **Kettenskript:** Löst selbst: Listenkonflikte, falsche `;` in `.dpr`/`.dpk`-Listen nach konfliktfreiem Merge (`fix-terminators.ps1`), Profiltest-Erwartungen (Branch-Seite ohne `unit-name-mismatch`), `Architektur.md` und `Konfiguration.md` (Branch-Seite ohne Teile übersprungener Branches), H2443 und E2532. Jeder andere Konflikt hält an.
- **Leck-Monitor (seit 177):**
  - Felder im `TearDown` freigeben.
  - Einmal-Belegungen der RTL im `[SetupFixture]` vorab auslösen; `[IgnoreMemoryLeaks]` nur mit Begründung.
  - Bei reinen Leck-Fehlschlägen bis zu sechs Läufe; gilt als zeitabhängig, wenn jeder gemeldete Test mindestens einmal sauber war.
- **Weitere Fixes in 78–97:** E2029 (Listentrenner), Profilerwartungen (#269, #91, #124, #125), Konflikte `UsesClause` (#284), `Shell.Composition` (#283: Mitschnitt rotiert und weicht aus; Methodendeklaration hinter die Felder), `DiskFileSystem` (#62: `EArgumentException` und `EOSError`), `System.Classes` im Index-Test, RotatingFileStream-Tests (`WillRaiseDescendant`).
- Die IDE sortiert `DCCReference` um und fügt Leerzeilen ein. Reine Umsortierungen und Leerraum-Änderungen werden verworfen.

## Umbenennung in Argus (#403, 09.10.2026)
- **GitHub:** Das Repository heißt jetzt `xKnockOut/Argus-IDE-Expert` (vom User umbenannt, alte URLs leiten weiter). Der lokale Ordner `C:\Projekte\BetterDelphiLSP\repo` bleibt, bis der User ihn selbst umbenennt.
- **Code:** Präfix `Argus.*` statt `BDLsp.*` in Units, Ordnern, `.dpk`, `.dproj`; Projektgruppe `Argus.groupproj`; Anwendung `Application\ArgusServer.dpr` → `ArgusServer.exe`; Tests `Tests\Argus.Tests.dpr` → `Argus.Tests.exe`; Plugin `Argus.IdePlugin.bpl`, Typ `TArgusCodeInsightManager`.
- **Namen nach außen:** Code Insight-Manager „Argus IDE Expert“, `serverInfo.name`, `source` der Diagnosen und SARIF-Werkzeug „Argus“. Befehle des Servers `argus.server.compile`, `argus.server.selectBuild`, `argus.server.status`; Editor-Abschnitt `argus` (VS Code `argus.*`); Cache `%LOCALAPPDATA%\Argus`, Compiler-Ausgabe `%TEMP%\Argus\dcc-…`.
- **Abwärtskompatibel:** `argus.json` und `argus-baseline.json`; fehlen sie, gelten `delphi-lsp.json` bzw. `delphi-lsp-baseline.json` (`ExistingOrLegacyFile`, `IsConfigurationFileName`). Das Plugin liest `HKCU\Software\Argus\IdePlugin`, ersatzweise den alten Schlüssel `HKCU\Software\BetterDelphiLSP\IdePlugin`; zeigt dessen `ServerPath` auf eine fehlende exe, gelten die Vorgaben.
- **Beim User nach dem ersten Bau nötig:**
  - Altes Package `BDLsp.IdePlugin.bpl` in der IDE entfernen, `Output\Win32\Debug\Bpl\Argus.IDE.Expert.bpl` installieren, im Code Insight-Manager „Argus IDE Expert“ wählen.
  - Der benutzerdefinierte LSP-Eintrag `UserDefined\BetterDelphiLSP` zeigt noch auf `BetterDelphiLSP.exe`: im Dialog auf `ArgusServer.exe` umstellen (Name `Argus`).
  - Alte Ausgaben (`BetterDelphiLSP.exe`, `BDLsp.*.bpl/.dcp`, `%LOCALAPPDATA%\BetterDelphiLSP`) können gelöscht werden.
- **Feature-Kette:** Beim Einmergen von `main` in die übrigen Branches folgen Umbenennungen von Dateien meist automatisch. Neue Units der Branches und ihre uses-Einträge danach nach denselben Regeln umbenennen: `BDLsp` → `Argus`, `bdlsp` → `argus`, `BetterDelphiLSP` → `ArgusServer` in `.dproj`/`.groupproj`/`.dpr`, sonst `Argus`; `delphi-lsp.json` → `argus.json`. Danach muss `git grep -n "BDLsp\|BetterDelphiLSP"` leer sein, außer an den Stellen für Abwärtskompatibilität.
- **Offen:** Gruppenbau und Tests in der IDE (in der Cloud nicht baubar). Schichten `Argus.Core/UI/IDE` und eigenes `Argus.Tests.dpr` für das Plugin folgen mit #406 und #415.

## Stand nach diesem Vorgang
- Gruppenbau `Argus.groupproj` Win64 und Plugin Win32 0/0/0, 1022/1022 Tests (zwei Läufe), Delphi des Users läuft mit dem neuen Plugin. (Kette: `main` = `2a4f2fd`, 964 Tests.)
- Zwischencommit `e545259` auf `main` hat 5 rote BinaryForm-Tests (falsches Ersetzen), behoben im direkt folgenden `2a4f2fd`.
- Offen: Issue für Deklarationen aus Include-Dateien (Entscheidung des Users), Ursache der Leck-Meldungen im vollen Testlauf, im Plugin Vervollständigung, Parameterhilfe und Error Insight.
