# 0017: Plugin in Kern-Package und Add-on-Packages je Modul aufteilen

- Status: Angenommen
- Datum: 2026-10-31, fortgeschrieben 2026-11-01 (Laden, Entladen, Versionen)
- Bezug: #1454 Modul-Schalter, #1455 Module melden sich über Verträge an, #1456 Pilot mit dem Debugger; ersetzt den Grundsatz „ein BPL“ aus [ADR 0006](0006-ide-plugin.md) und [ADR 0012](0012-gemeinsamer-text-code.md); Code-Review A-09

## Kontext

Das Plugin war als dünner LSP-Client für Hover und Vervollständigung geplant (ADR 0006). Inzwischen ist es eine Suite: 730 Units mit rund 381 000 Zeilen (Stand `main`, e6527a4a), davon Einstellungen 42 000, Willkommensseite 40 000, Editor 40 000, Tracker 38 000, Debugger 23 000 und Versionsverwaltung 13 000 Zeilen. Alles liegt in einem Design-Time-Package `Atlas.IDE.Expert`.

Bisher wurde das Aufteilen dreimal verworfen:
- ADR 0002 (07.10.2026): „Feinere Packages je Feature: mehr Verwaltung ohne erkennbaren Nutzen“. Damals gab es nur den Server.
- ADR 0006, Fortschreibung vom 16.10.2026: „Alles bleibt in einem BPL; ein Aufteilen in Packages ist damit später möglich, aber nicht nötig.“
- ADR 0012 (15.10.2026): Ein zweites BPL `Atlas.Text.bpl` wurde verworfen, weil es mitgeliefert, registriert und in der richtigen Reihenfolge geladen werden müsste und Updates erschwert.

Fast jede Funktion lässt sich einzeln abschalten, und abgeschaltete Teile starten nicht (`TAtlasFeatureTable`). Wer nur Code Insight will, installiert trotzdem die ganze Suite und lädt sie in den Adressraum der IDE.

Gemessen an den uses-Verweisen zwischen Funktionsgruppen ist der Debugger am losesten gekoppelt. Willkommensseite, Tracker und Versionsverwaltung hängen eng zusammen (Willkommensseite → Tracker 41, → Versionsverwaltung 25 Verweise). Zentral kennen heute die Kompositionswurzel `Atlas.IDE.CodeInsight.Composition`, die Einstellungsseiten, die Befehle und `Atlas.UI.Strings` alle Module direkt.

## Entscheidung

Ziel ist ein Kern-Package plus je Modul ein eigenes Design-Time-Package, das man einzeln installiert (Variante C der Analyse vom 31.10.2026, auf Wunsch von Marco feiner geschnitten: elf Packages; Zuordnung aller Units in [0017-unit-zuordnung.md](0017-unit-zuordnung.md), Querverweise in der Fortschreibung unten):

| Package | Requires | Inhalt |
|---|---|---|
| `Atlas.IDE.Core` | rtl, vcl, vclwinx, designide | Foundation, LSP-Sitzung, Code Insight, Editor, Diagnosen (Anzeige aller Meldungen des Servers: Syntaxfehler, Compilermeldungen, Prüfbefunde), Gliederung, Versionsverwaltung, Rahmen für Einstellungen, Palette und Statusfeld, Verträge der Module, `Atlas.Text` als Quelltext |
| `Atlas.IDE.Debugger` | `Atlas.IDE.Core` | Debugger |
| `Atlas.IDE.Tracker` | `Atlas.IDE.Core` | Issue-Tracker und Build-Server |
| `Atlas.IDE.Welcome` | `Atlas.IDE.Core` | Willkommensseite |
| `Atlas.IDE.Analysis` | `Atlas.IDE.Core` | Architekturübersicht, Unit-Beziehungen, Symbolpfad, Hotspots |
| `Atlas.IDE.Designer` | `Atlas.IDE.Core` | Designer-Leiste und Komponentensuche im Formular-Designer |
| `Atlas.IDE.Search` | `Atlas.IDE.Core` | Suche, Unitsuche, Abfrage |
| `Atlas.IDE.Rules` | `Atlas.IDE.Core` | Prüfregeln: schaltet die Regelprüfung im Server ein; Seite „Prüfregeln“ mit Regeltabelle und Profilen, Baseline, Sammelkorrektur, Erklären, Unterdrücken am Element |
| `Atlas.IDE.Tests` | `Atlas.IDE.Core` | DUnitX-Ergebnisse und Testbefehle |
| `Atlas.IDE.Build` | `Atlas.IDE.Core` | Build-Werkzeuge: Release-Wächter, Schranke vor dem Kompilieren, Compilerschalter, Build-Zusammenfassung, „Öffnen und bauen“; Aufgaben, Startprofile |
| `Atlas.IDE.Bookmarks` | `Atlas.IDE.Core` | Lesezeichen, Notizen |

Regeln:
- Kein Modul requiret ein anderes. Querbezüge (Willkommensseite zeigt Issues, Hover zeigt Debugger-Werte, Palette öffnet die Unitsuche) laufen über Verträge im Kern; fehlt das Modul, bleibt der Beitrag leer.
- Der Kern kennt kein Modul. Module melden Einstellungsseiten, Befehle, Menüeinträge, Statusfeldzeilen, Tipps und Bereiche der Willkommensseite beim Laden an und beim Entladen ab.
- Ein nicht installiertes Modul verhält sich wie ein abgeschaltetes (Modul-Schalter aus #1454).
- Im Kern bleibt, was viele andere Teile benutzen oder ohne das Code Insight nicht brauchbar ist: die Anzeige der Diagnosen (ohne sie sähe man nicht einmal Syntaxfehler; die Prüfregeln selbst laufen im Server, aber nur mit `Atlas.IDE.Rules`, siehe unten), Compilermeldungen und Prüfen nach dem Speichern (Quelle der Diagnosen), Benachrichtigungen, Rückgängig, Doku, Versionsverwaltung (Grundlage für Willkommensseite, Tracker, Tests und Änderungsmarken im Editor). Der allgemeine Tooltip `Atlas.UI.Notes.Tip` wandert vorher nach Foundation.
- Möglicher Schnitt nach dem Pilot (vermerkt, nicht entschieden): den Kern in `Atlas.IDE.Base` (Foundation, Rahmen für Einstellungen, Befehle, Statusfeld, Hosts, Style, Texte, Benachrichtigungen, Projekte, Dateien, Verträge, LSP-Client mit Serverstart erst auf Anfrage eines Moduls) und `Atlas.IDE.CodeInsight` (Vervollständigung, Hover, Signatur, Inlay-Hints, Gliederung, Anzeige der Diagnosen, Compilermeldungen, Snippets) teilen. Dann käme z. B. Bookmarks ohne Code Insight aus. Preis: zwölftes Package (48 Builds), Code Insight braucht immer zwei Installationen, und seine Beiträge an Editor, Statusfeld und Hover laufen ebenfalls über Verträge.
- Versionsverwaltung als eigenes Package ginge nur mit einer zweiten Ebene (Willkommensseite und Tracker requiren sie); vorerst nicht vorgesehen.
- Prüfregeln laufen nur, wenn `Atlas.IDE.Rules` installiert und `ruleChecks.enabled` an ist (Marco, 31.10.2026). Sonst teilt der Kern dem Server beim Start und bei jeder Änderung mit, dass er keine Regeln prüfen soll; es erscheinen nur Syntaxfehler und Compilermeldungen. Hat das Projekt Prüfregeln in der `atlas.json`, das Package fehlt aber, zeigt Atlas einmal je Projekt einen Hinweis. `--check` und MCP sind davon nicht betroffen.
- `Atlas.Common` und `Atlas.Windows` bleiben außerhalb der IDE (ADR 0006, ADR 0012). Die Sprachlogik bleibt im Server, alle Packages nutzen die eine Sitzung des Kerns.

Reihenfolge:
1. #1454: Module als Ganzes schaltbar, weiter ein BPL.
2. #1455: Module melden sich über Verträge an; `Tools/Check-PackageDependencies.ps1` verbietet Verweise vom Kern auf Module und zwischen Modulen.
3. #1456: Kern-Package und Debugger als erstes Add-on (Pilot).
4. Die übrigen Module erst, wenn der Pilot Installieren, Entladen, Beenden und Bauen mit `cc.ps1` ohne Probleme zeigt. Zeigt er das nicht, bleibt es bei Schritt 2 und dieses ADR wird fortgeschrieben.

Versionen (Marco, 31.10.2026):
- Schritte 1 und 2 erscheinen in 1.x. Für Nutzer kommen nur Schalter und ein Profil dazu; Installation, BPL-Name und Einstellungen bleiben.
- Die Aufteilung selbst ist Version **2.0**, weil sie jede Installation bricht: `Atlas.IDE.Expert<Version>.bpl` wird zu `Atlas.IDE.Core<Version>.bpl` plus Add-ons, der alte Eintrag unter Known Packages muss weg, das Release-Paket ändert seinen Aufbau, ein Update heißt neu installieren statt über den alten Ordner entpacken.
- Der Pilot (Schritt 3) erscheint als Vorabversion `2.0.0-beta.1`, 1.x-Nutzer sind davon nicht betroffen. 2.0.0 erscheint, wenn alle elf Packages getrennt sind.

## Alternativen

- **Ein BPL wie bisher (Variante A):** keine Installationswahl, die Suite lädt immer ganz.
- **Ein BPL mit Modul-Schaltern (Variante B):** bekommt die Schritte 1 und 2, bleibt aber ohne Wahl bei der Installation; als Zwischenstand weiter gültig.
- **Zwei Editionen aus einer Quelle (Variante D):** „Code Insight“ und „Suite“ als zwei BPLs, von denen genau eines installiert wird. Weniger Builds als C, aber nur zwei Stufen statt einer Wahl je Modul.

## Folgen

- **Builds:** je Package Win32 und Win64 für Delphi 12 und 13; bei elf Packages 44 statt 4 Builds je Release. `Atlas.groupproj` baut den Kern zuerst.
- **Bauen mit `cc.ps1` (ADR 0007):** Solange ein Add-on geladen ist, hält die IDE auch den Kern; zum Neubauen des Kerns werden die Add-ons mit entladen.
- **Installation (ADR 0016):** Das Release-Paket enthält Kern und Add-ons je Plattform. Der Kern wird zuerst installiert und muss für den Windows-Lader auffindbar sein, wenn ein Add-on lädt.
- **Package-Art (Marco, 31.10.2026):** Auch der Kern (bzw. später Base) bleibt ein Design-Time-Package, kein Runtime-Package. Es gibt keinen Laufzeitteil, und der Kern braucht selbst `designide`. Der Kern steht selbst unter Known Packages, denn die IDE ruft `Register` nur für installierte Packages auf; nur dort startet er Sitzung, Hosts, Statusfeld und Einstellungsseiten. Die Add-ons requiren den Kern; der Windows-Lader lädt ihn mit. Ablauf beim Start: Kern-`Register` startet Sitzung und Hosts, danach melden die Add-ons in ihrem `Register` ihre Beiträge über die Verträge an. Alle Packages bekommen `DESIGNONLY` und dasselbe `LIBSUFFIX AUTO`; die Add-ons übersetzen gegen die `.dcp` des Kerns. Ist der Kern nicht installiert, zeigt ein Add-on nur den Hinweis „Atlas-Kern nicht installiert“. Ein Runtime-Kern mit dünnen Design-Time-Hüllen wurde verworfen: ein Package mehr ohne Gewinn.
- **Entladen:** Add-ons bauen ihre Beiträge ab, bevor der Kern abgebaut wird. Einträge in den Hauptthread nur über `TAtlasMainThread` des Kerns; Editorleisten, Zeilenleisten-Spalten und Fenster nur über die Hosts des Kerns (`CLAUDE.md`).
- **Texte und Schema:** `Atlas.UI.Strings` und die erzeugte Schema-Unit werden je Package geteilt.
- **Tests:** Es bleibt ein Testprojekt `Atlas.Tests`, das alle Quellen übersetzt (kein Testprojekt je Package: Tests laden keine BPLs, und mit RAD Studio Starter wäre jedes Projekt ein eigener Lauf über `cc.ps1`). Testordner je Package (`Tests/IDE.Core`, `Tests/IDE.Debugger` …) und je Modul eine DUnitX-Kategorie, damit sich die Tests eines Moduls allein ausführen lassen. Die Prüfskripte kennen die neuen Packages.

## Fortschreibung: Laden, Entladen, Versionen (Review 2026-11-01)

- Bezug: Review dieses ADR gegen den Code von `Pilot-2.0.0-beta.1` (6364e487, noch ein Package `Atlas.IDE.Expert`); #1454, #1455, #1456; ADR 0006, 0012, 0016
- Korrektur: Die Texte liegen in `Atlas.UI.Strings`, nicht in `Atlas.Core.Strings`; oben an beiden Stellen berichtigt.
- Die Entscheidung oben bleibt: Variante C mit elf Packages, Debugger als Pilot, Design-Time-Kern ohne Runtime-Teil, ein Testprojekt, `Atlas.Text` als Quelltext im Kern. Diese Fortschreibung ergänzt, was beim Laden, Entladen und Versionieren mehrerer BPLs gilt, und benennt, was noch offen ist.

### Befund am Code

Geprüft am 01.11.2026; Zahlen gelten für diesen Stand.

| Thema | Befund | Datei |
|---|---|---|
| Kompositionswurzel | 6 515 Zeilen, kennt alle Module per uses; 55 Feature-Slots über `Features.Add`/`AddWanted`, davon zehn für den Debugger: `Visualizers`, `DebugExceptions`, `DebugOwnCode`, `DebugExceptionBar`, `DebugInlineValues`, `DebugUnavailable`, `DebugAccessViolation`, `DebugDialogCompletion`, `DebugEvaluate`, `DebugStepFilter` | `Atlas.IDE.CodeInsight.Composition` |
| Feature-Tabelle | Start in fester Reihenfolge, Abbau rückwärts; ein Fehler im Stop hält den Abbau nicht an (`TAtlasTeardown.Failures`) | `Atlas.Core.Diagnostics.FeatureTable` |
| Einstellungsseite | 10 206 Zeilen, baut die Abschnitte aller Module selbst (`AddWelcomeSection`, `AddIssues*Section`, `AddTracker*Section`, `AddTasksSection` …) | `Atlas.UI.Settings.Page` |
| Einstellungs-Record | `TAtlasPluginSettings = record` mit Feldern aller Module, dazu zentrale Migrationen und `SchemaCheck` | `Atlas.Core.Settings.Plugin` |
| Schema | eine erzeugte Unit (6 513 Zeilen) aus `schemas/atlas-plugin.schema.json` | `Atlas.Core.Settings.PluginSchemaData` |
| Texte | ein Enum `TAtlasTextId` mit DE/EN-Tabelle (7 908 Zeilen); ein Enum lässt sich nicht über Packages verteilen | `Atlas.UI.Strings` |
| Modul-Identität | Tasten gelten als Atlas-Tasten, wenn ihr Modul `GetModuleName(HInstance)` ist (`FAtlasModule`, `OriginOfModule`); `OwnClass` vergleicht `FindClassHInstance(…) = HInstance`; die Stackerfassung erkennt eigene Rahmen am Adressbereich von `HInstance`. Mit mehreren BPLs gälten Tasten, Klassen und Rahmen eines Add-ons als fremd. | `Atlas.IDE.Commands.KeyMap`, `Atlas.IDE.CodeInsight.Composition`, `Atlas.IDE.Diagnostics.StackCapture` |
| Datenordner und Log | `Welcome.Help`, `Welcome.Setup`, `Welcome.WhatsNew`, `Commands.Usage` suchen Daten neben `GetModuleName(HInstance)`; `CodeInsight.Manager` leitet Ordner und Namen des Diagnoselogs daraus ab (aus `Atlas.IDE.Expert370.log` würde `Atlas.IDE.Core370.log`). Richtig macht es `Atlas.UI.Style.Symbol` mit `FindClassHInstance(TAtlasSymbolImages)`. | `Source/IDE/Welcome`, `Source/IDE/Commands`, `Source/IDE/CodeInsight` |
| Package-Schalter | `{$DESIGNONLY}`, `{$IMPLICITBUILD ON}`, `{$LIBSUFFIX AUTO}`, requires `rtl, vcl, vclwinx, designide`, alle `Atlas.Text`-Units unter `contains` | `Atlas.IDE.Expert.dpk` |

Verweise auf den Debugger aus Units, die im Kern bleiben: Kompositionswurzel (14 Debug-Units), Befehle (`Commands.Bindings`, `.Editor`, `.MainMenu`: `StepInto`, `StepFilter`, `Exceptions`, `Evaluate`), Einstellungen (`Settings.EventBreakNames`, `.VisualizerKinds`, `UI.Settings.Page`: `EventBreak`, `Visualizers`, `OwnCode`), Hover (`Hover.Editor`: `Visualizers`). Der Tracker (`Tracker.Attach`) verwendet `Debug.Session`, `.Sources`, `.Exceptions`, `.Note`, `.CallStack`. Der Debugger selbst verwendet nur Gruppen, die im Kern bleiben.

Verweise zwischen geplanten Add-ons (Units des Verbrauchers mit mindestens einem Verweis, Ordnerzuordnung aus [0017-unit-zuordnung.md](0017-unit-zuordnung.md)): Welcome → Tracker 10 (auf 30 verschiedene Tracker-Units), Welcome → Bookmarks 3, Welcome → Build 3, Tests → Build 3, Tracker → Bookmarks 2, Tracker → Debugger 1, Tracker → Build 1. Alle werden Verträge im Kern.

Die Zuordnung aller 730 Units zu Packages steht jetzt im Repo: [0017-unit-zuordnung.md](0017-unit-zuordnung.md). Die Analyse vom 31.10. enthielt nur Summen je Package; die Rules-Units sind dort noch ein Vorschlag.

### Drei Mechaniken von Delphi-Packages

1. **Lade- und Register-Reihenfolge.** Die IDE lädt Known Packages in Registry-Reihenfolge, und die ist nicht garantiert. Lädt sie ein Add-on vor dem Kern, sucht der Windows-Lader `Atlas.IDE.Core<Suffix>.bpl` im Ordner von `bds.exe`, in den Systemordnern und auf dem PATH, nicht im Ordner des Add-ons. Ist der Kern schon im Prozess, löst sich der Import über den Modulnamen auf. Seine Initialisierungsabschnitte laufen beim Laden, sein `Register` aber erst, wenn die IDE in ihrer Liste beim Kern ankommt, also womöglich nach dem `Register` des Add-ons.
2. **Entladen.** `UnloadPackage` ruft `Finalize` eines Packages vor `FreeLibrary` auf, auch wenn ein anderes geladenes Package es noch importiert. Wird der Kern bei installiertem Add-on abgewählt (Package-Dialog oder `cc.ps1 unload-package`), laufen seine Finalisierungen, während das Add-on noch lebt. Ob die IDE das bei Design-Packages mit `requires` selbst abfängt, ist nicht belegt; der Pilot prüft es (P7), es wird nicht vorausgesetzt.
3. **ABI-Kopplung.** Add-ons übersetzen gegen die `.dcp` des Kerns. Jede Änderung am Interface-Teil einer Kern-Unit verschiebt Methodentabellen, und Delphi prüft das zur Laufzeit nicht: Kern 2.0.1 mit Debugger 2.0.0 stürzt ab, statt sauber zu scheitern. `LIBSUFFIX` trennt nur die IDE-Version, nicht die Atlas-Version. Generische Klassen (`TList<string>`) werden je Package instanziiert und sind zur Laufzeit verschiedene Typen (`is`, `as`, `ClassType` scheitern, Methodenaufrufe nicht).

Wer eine dieser Mechaniken im Pilot widerlegt, schreibt das Ergebnis hier fort.

### Regeln für Module und Verträge

Status: **vorgeschlagen**, gilt erst nach Marcos Bestätigung (offene Entscheidung 6). Danach Kurzfassung in `CLAUDE.md`, Begründung in `docs/Architektur.md`, bevor #1455 beginnt.

1. **Registrieren ohne Reihenfolge.** Verträge und Registries des Kerns sind ab der Unit-Initialisierung verfügbar (verzögert erzeugte Singletons in `Atlas.Core.*.Contract`-Units oder einer Modul-Registry), nicht erst nach `Register` des Kerns. Das `Register` eines Add-ons startet nichts, es meldet nur einen Modul-Deskriptor an (Modul-ID, Anzeigename, Mindeststufe für den abgesicherten Start #722, `Start`, `Stop`, `IsActive`). Gestartet und gestoppt wird nur über die `TAtlasFeatureTable` des Kerns.
2. **Spät ankommende und verschwindende Module.** Der Kern startet ein Modul auch, wenn es nach seinem eigenen Start angemeldet wird (Add-on bei laufender IDE installiert), und stoppt es bei Abmeldung. Wer Beiträge anderer Module anzeigt (Willkommensseite, Hover, Statusfeld, Palette), reagiert auf An- und Abmeldung, statt einmal beim Start zu fragen.
3. **Abmelden ist synchron und vollständig.** Nach dem Abmelden erreicht kein Aufruf mehr das Modul: keine Serverantwort, kein `TAtlasMainThread`-Eintrag, kein Timer, kein Ereignis. Vorbild ist `IAtlasCompletionProvider` (ADR 0006: nach `Cancel` erreicht nichts mehr die alte Senke).
4. **Jede Anmeldung hat einen Besitzer.** Alles, was ein Modul im Kern anmeldet (Feature-Slot, Einstellungsabschnitt, Befehl, Menüeintrag, Statusfeldzeile, Editorleiste, Dock-Fenster, Tipp, Bereich der Willkommensseite, Hover-Beitrag), trägt die Modul-ID. Abmelden entfernt alles in umgekehrter Reihenfolge; umgesetzt als `IAtlasModuleScope`, der jede Anmeldung sammelt und bei Freigabe löst.
5. **Kern-Finalisierung stoppt zuerst die Module.** Die Finalisierung des Kerns ruft `StopAll` der Feature-Tabelle vor dem Abbau eigener Registries auf und setzt danach ein Flag „Kern abgebaut“. Add-on-Finalisierungen melden sich nur ab, wenn das Flag nicht gesetzt ist.
6. **Vertragsinhalte.** Verträge tauschen Interfaces mit GUID, Records, `TArray<T>` und Methodenreferenzen. Keine generischen Klassen zur Typprüfung über Package-Grenzen, keine `ClassName`-Vergleiche über Grenzen. Verträge beschreiben Fähigkeiten, nicht Module (`IAtlasIssueSource`, nicht `IAtlasTrackerForWelcome`).
7. **Versions-Handschlag.** Der Kern führt eine Vertragsversion als Konstante und als exportierte Funktion `AtlasCoreContractVersion`. Ein Add-on prüft sie als Erstes in `Register` über `GetProcAddress` (damit die Prüfung auch bei verschobenem ABI nicht abstürzt) und zeigt bei Abweichung „Atlas-Kern passt nicht zu diesem Modul“, ohne sich anzumelden.
8. **Modul-Identität.** „Ist das Atlas?“ entscheidet nie `HInstance` oder `GetModuleName(HInstance)` eines einzelnen Moduls, sondern der Modulkatalog des Kerns (geladene Atlas-HMODULEs), ersatzweise das Präfix `Atlas.IDE.` im Dateinamen. Ressourcen des Kerns lädt man über `FindClassHInstance` einer Kern-Klasse; den Installationsordner liefert eine Kern-Funktion. Der Maus-Hook in `Atlas.UI.Tracker.Capture` (`SetWindowsHookEx` mit `HInstance`) bleibt, er gehört zum eigenen Modul.
9. **Modulkatalog: feste Liste plus Anmeldung.** Der Kern kennt die eigenen Atlas-Module als statische Daten (ID, Anzeigename), damit er „nicht installiert“ zeigen und auf fehlende Packages hinweisen kann. Maßgeblich zur Laufzeit ist aber die Anmeldung: Jedes Package, das sich mit einem Deskriptor anmeldet, ist ein Modul, auch ein fremdes (Erweiterung eines anderen Entwicklers, Atlas-SDK #1459). Fremde Module erscheinen nur, solange sie installiert sind; sie nutzen dieselben Verträge, denselben Versions-Handschlag (Regel 7) und dieselbe Besitzer-Regel (Regel 4) wie eigene. „Der Kern kennt kein Modul“ heißt: kein Code und kein uses; die feste Liste ist nur Anzeige, keine Zugangsvoraussetzung.

Prüfbar in `Tools/Check-PackageDependencies.ps1` (mit #1455): Regel 8 (kein `GetModuleName(HInstance)`-Vergleich außerhalb des Kerns) und Regel 6 (kein `is TList<`/`is TDictionary<` über Vertragsgrenzen, soweit statisch erkennbar).

### Auffindbarkeit des Kerns

**Offen** (Entscheidung 1). Bis zur Entscheidung gilt nur: Der Kern muss für den Windows-Lader auffindbar sein, sobald ein Add-on vor ihm geladen wird; der Ordner des Add-ons reicht dafür nicht. Optionen:

- a) Release-Ordner je Plattform auf den PATH: Handarbeit, zwei Ordner für zwei IDE-Bitbreiten.
- b) BPLs nach `$(BDSCOMMONDIR)\Bpl`: liegt schon auf dem PATH, mischt sich mit fremden Packages.
- c) Darauf bauen, dass der Kern vor den Add-ons geladen ist und der Import über den Modulnamen aufgeht: nur so sicher wie die Registry-Reihenfolge (P1/P2).
- d) a oder b, zusätzlich c. Empfehlung des Reviews: d, mit b als Vorgabe in der Anleitung.

Unabhängig davon: je BPL-Name nur eine Kopie auf dem Rechner; eine ältere `Atlas.IDE.Core<Suffix>.bpl` auf dem PATH verdrängt die neue. Installation: Kern zuerst, dann Add-ons; Deinstallation: Add-ons zuerst.

### Weitere Folgen

- **Release (`release.yml`):** ZIP mit `Win32\` und `Win64\`, darin Kern und alle Add-ons samt Map-Dateien; `LIESMICH` im Paket mit Reihenfolge von Installation und Deinstallation.
- **Versionen:** Alle Packages einer Auslieferung tragen dieselbe Version; ein einzelnes Modul wird nie für sich aktualisiert (Mechanik 3). `Tools/Set-Version.ps1` und `Check-Version.ps1` bearbeiten bzw. prüfen alle Plugin-`.dproj`.
- **Doku:** `docs/Installation.md` und `docs/RAD-Studio.md` beschreiben Reihenfolge, Deinstallation (1.x: `Atlas.IDE.Expert<Suffix>.bpl` aus Known Packages entfernen) und „Update heißt neu installieren“. `docs/Release-Notizen/2.0.0-beta.1.md` sagt, was im Beta-Kern noch steckt (alle Module außer Debugger).
- **CHANGELOG:** Einträge nennen ab 2.0 das Modul (z. B. „Debugger: …“).
- **Fehlendes Modul nach Update:** Ist ein Modul eingeschaltet, aber nicht installiert, zeigt der Kern das einmal je IDE-Sitzung mit Verweis auf die Installationsanleitung, damit ein vergessenes Add-on nicht still fehlt.
- **Diagnose:** Diagnoselog und Registry-Schlüssel `HKCU\Software\Atlas\IdePlugin` behalten ihren Namen trotz neuem BPL-Namen (heute leitet `CodeInsight.Manager` den Log-Namen vom BPL ab); Stacktraces lesen die Map-Datei des jeweiligen BPL; Fehlerbericht und Update-Prüfung nennen die installierten Add-ons.
- **Prüfregeln nur mit `Atlas.IDE.Rules`:** Hat ein Projekt Regeln in der `atlas.json`, ist das Package aber nicht installiert, zeigt die IDE keine Prüfbefunde, während `--check` in der CI dieselben Befunde meldet und rot sein kann. Das ist so gewollt (Marco, 31.10.2026, oben unter „Regeln“); der Hinweis je Projekt ist die einzige Brücke. Ob das so bleibt, ist Entscheidung 8.
- **`{$IMPLICITBUILD OFF}`** für Kern und Add-ons: Ein Package, das andere requiren und das in der bauenden IDE geladen sein kann, darf nicht implizit gebaut werden.

### Pilot (#1456): Verträge und Abnahme

Ergänzt Schritt 3 und 4 unter „Reihenfolge“.

Verträge, die der Pilot braucht (Namen nach `docs/Architektur.md` prüfen):

| Verbraucher im Kern | Heutiger Verweis | Vertrag (Vorschlag) |
|---|---|---|
| Hover, Kompositionswurzel | `Debug.Visualizers` | `IAtlasHoverValueSource`: Wert unter der Maus im Debugger |
| Vervollständigung | `Core.Debug.DialogCompletion` (über `Completion.Providers.Expression`) | `IAtlasCompletionHost` für fremde Eingabefelder (Auswerten/Ändern, Haltepunkte) |
| Befehle | `StepInto`, `StepFilter`, `Exceptions`, `Evaluate` | Befehle über die Befehlsregistrierung mit Besitzer, keine direkten uses |
| Tracker (im Pilot noch Kern) | `Session`, `Sources`, `Exceptions`, `Note`, `CallStack` | `IAtlasDebugReportSource`: Aufrufliste, Ausnahme, Notiz für den Fehlerbericht; fehlt er, bleibt der Abschnitt leer |
| Einstellungen | `Visualizers`, `OwnCode`, `EventBreak` | Einstellungsabschnitte des Debuggers über einen Abschnittsvertrag; die Datenfelder nach Entscheidung 3 |
| Kompositionswurzel | `DisplayRules` (eigenes `Register`) | bleibt im Add-on; die IDE ruft `Register` jeder Unit des Add-ons selbst |
| Kompositionswurzel | `Trace`, `Unavailable`, `InlineValues`, `ExceptionBar`, `AccessViolation`, `EventBreak` | nur Feature-Slots; wandern mit dem Modul-Deskriptor ins Add-on |

`tests.debug` (Test am Cursor debuggen, #585) gehört zum Modul Tests und nutzt den Debugger der IDE direkt über die Open Tools API, nicht das Atlas-Debugger-Modul; im Modulkatalog vermerken.

Abnahme, jeder Fall mit Delphi 12 und 13, Win32 und Win64. Bestanden heißt: keine Ausnahme, `TAtlasTeardown.Failures` leer, Diagnosemodus (#479) ohne Einträge, IDE beendet sich ohne Meldung. Ergebnis als Tabelle in #1456.

- P1. Frischer Start, Known Packages in der Reihenfolge Kern, Debugger.
- P2. Frischer Start, Reihenfolge Debugger, Kern (Registry-Einträge so anlegen).
- P3. Nur Kern installiert: Code Insight vollständig, keine Debugger-Beiträge, Schalterseite zeigt „nicht installiert“.
- P4. Nur Debugger installiert (Kern liegt im Ordner, steht nicht unter Known Packages): Hinweis „Atlas-Kern nicht installiert“, kein Absturz.
- P5. Debugger bei laufender IDE hinzufügen: Beiträge erscheinen sofort.
- P6. Debugger bei laufender IDE abwählen: Beiträge verschwinden; kein AV beim nächsten Hover, Debuggen, Beenden.
- P7. Kern bei installiertem Debugger abwählen: Meldung der IDE, Reihenfolge der Finalisierungen, Absturz ja/nein festhalten und hier unter Mechanik 2 fortschreiben.
- P8. `cc.ps1`: Kern neu bauen bei geladenem Debugger (erwartet: Debugger wird mit entladen, Bau läuft, beide laden wieder).
- P9. Debugger mit alter Vertragsversion gegen neuen Kern: Hinweis, keine Anmeldung.
- P10. Desktop-Wiederherstellung: Dock-Fenster des Debuggers offen, IDE beenden, Debugger deinstallieren, IDE starten.
- P11. `pwsh Tools/Build-Test.ps1` (Win64-Gruppe, Win32-Plugin) und alle Prüfskripte grün, 0/0/0.

Scheitert der Pilot an einem Fall ohne Abhilfe, greift Schritt 4: Es bleibt beim Stand nach #1455 (erzwungene Grenzen, Modul-Schalter), und dieses ADR wird fortgeschrieben.

### Offene Entscheidungen (Marco)

1. **Auffindbarkeit des Kerns:** a PATH, b `$(BDSCOMMONDIR)\Bpl`, c Ladereihenfolge, d a oder b plus c. Empfehlung: d mit b.
2. ~~**#1455 in 1.x oder in 2.0?**~~ **Entschieden (Marco, 01.11.2026):** Der ganze Umbau ist Version 2.0.0, auch #1454 und #1455; siehe „Versionen (neu)“ unten. 1.x (`release/1.2`) bekommt davon nichts.
3. **Einstellungs-Record und Schema:** a bleiben ganz im Kern (Daten, kein Code; jede neue Moduleinstellung erzwingt Kern- und damit alle Add-on-Bauten; ein fremdes Add-on (Atlas-SDK #1459) hätte damit keine eigenen Einstellungen); b je Modul eigener Abschnitt mit Record, Schema-Teil, Migration und Validierung, der Kern speichert Abschnitte generisch. Empfehlung: a für den Pilot, b spätestens mit dem Atlas-SDK (#1459), weil fremde Module eigene Einstellungen brauchen.
4. **Texte:** a je Modul eigenes Enum und eigene Tabelle (`TAtlasDebugTextId`), Sprachwechsel über einen Vertrag; b Schlüssel als `string` mit Registry je Modul. Empfehlung: a; der Vertrag für den Sprachwechsel gilt auch für fremde Module.
5. **`Atlas.IDE.Expert.dproj` im Pilot behalten?** Empfehlung: nur auf `release/1.2`, auf `main` und im Pilot entfernen.
6. **Regeln 1 bis 9** oben bestätigen oder ändern.
7. **Quellbaum:** schicht-first wie heute (`Source/{Core,IDE,UI}/<Feature>`) oder package-first (`Packages/Atlas.IDE.Debugger/Source/{Core,IDE,UI}`). Package-first macht die Zuordnung zur Ordnerfrage und vereinfacht das Prüfskript, verschiebt aber viele Dateien. Bis zur Entscheidung werden keine Dateien verschoben, nur `contains` aufgeteilt.
8. **Prüfregeln nur mit `Atlas.IDE.Rules`:** bestätigen, obwohl IDE und `--check` sich widersprechen können, oder Regeln im Kern laufen lassen und nur die Regelseite ins Add-on legen.

### Versionen (neu, Marco 01.11.2026)

Ersetzt die ersten beiden Punkte unter „Versionen“ oben: Der ganze Umbau erscheint mit **2.0.0**, auch die Modul-Schalter (#1454) und die Verträge (#1455). 1.x (`release/1.2`) bleibt Wartungslinie für Fehlerbehebungen und bekommt nichts davon. Meilenstein auf GitHub: `v2.0.0` mit #1454, #1455, #1456. Der Pilot erscheint weiter als Vorabversion `2.0.0-beta.1`.
