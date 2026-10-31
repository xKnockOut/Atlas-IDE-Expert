# 0017: Plugin in Kern-Package und Add-on-Packages je Modul aufteilen

- Status: Angenommen
- Datum: 2026-10-31
- Bezug: #1454 Modul-Schalter, #1455 Module melden sich über Verträge an, #1456 Pilot mit dem Debugger; ersetzt den Grundsatz „ein BPL“ aus [ADR 0006](0006-ide-plugin.md) und [ADR 0012](0012-gemeinsamer-text-code.md); Code-Review A-09

## Kontext

Das Plugin war als dünner LSP-Client für Hover und Vervollständigung geplant (ADR 0006). Inzwischen ist es eine Suite: 730 Units mit rund 381 000 Zeilen (Stand `main`, e6527a4a), davon Einstellungen 42 000, Willkommensseite 40 000, Editor 40 000, Tracker 38 000, Debugger 23 000 und Versionsverwaltung 13 000 Zeilen. Alles liegt in einem Design-Time-Package `Atlas.IDE.Expert`.

Bisher wurde das Aufteilen dreimal verworfen:
- ADR 0002 (07.10.2026): „Feinere Packages je Feature: mehr Verwaltung ohne erkennbaren Nutzen“. Damals gab es nur den Server.
- ADR 0006, Fortschreibung vom 16.10.2026: „Alles bleibt in einem BPL; ein Aufteilen in Packages ist damit später möglich, aber nicht nötig.“
- ADR 0012 (15.10.2026): Ein zweites BPL `Atlas.Text.bpl` wurde verworfen, weil es mitgeliefert, registriert und in der richtigen Reihenfolge geladen werden müsste und Updates erschwert.

Fast jede Funktion lässt sich einzeln abschalten, und abgeschaltete Teile starten nicht (`TAtlasFeatureTable`). Wer nur Code Insight will, installiert trotzdem die ganze Suite und lädt sie in den Adressraum der IDE.

Gemessen an den uses-Verweisen zwischen Funktionsgruppen ist der Debugger am losesten gekoppelt. Willkommensseite, Tracker und Versionsverwaltung hängen eng zusammen (Willkommensseite → Tracker 41, → Versionsverwaltung 25 Verweise). Zentral kennen heute die Kompositionswurzel `Atlas.IDE.CodeInsight.Composition`, die Einstellungsseiten, die Befehle und `Atlas.Core.Strings` alle Module direkt.

## Entscheidung

Ziel ist ein Kern-Package plus je Modul ein eigenes Design-Time-Package, das man einzeln installiert (Variante C der Analyse vom 31.10.2026, auf Wunsch von Marco feiner geschnitten: elf Packages; Zuordnung aller Units und Querverweise in der Analyse, Abschnitt „Komplette Aufstellung“):

| Package | Requires | Inhalt |
|---|---|---|
| `Atlas.IDE.Core` | rtl, vcl, vclwinx, designide | Foundation, LSP-Sitzung, Code Insight, Editor, Diagnosen (Anzeige aller Meldungen des Servers: Syntaxfehler, Compilermeldungen, Prüfbefunde), Gliederung, Versionsverwaltung, Rahmen für Einstellungen, Palette und Statusfeld, Verträge der Module, `Atlas.Text` als Quelltext |
| `Atlas.IDE.Debugger` | `Atlas.IDE.Core` | Debugger |
| `Atlas.IDE.Tracker` | `Atlas.IDE.Core` | Issue-Tracker und Build-Server |
| `Atlas.IDE.Welcome` | `Atlas.IDE.Core` | Willkommensseite |
| `Atlas.IDE.Analysis` | `Atlas.IDE.Core` | Architekturübersicht, Unit-Beziehungen, Symbolpfad, Hotspots |
| `Atlas.IDE.Designer` | `Atlas.IDE.Core` | Designer-Leiste und Komponentensuche im Formular-Designer |
| `Atlas.IDE.Search` | `Atlas.IDE.Core` | Suche, Unitsuche, Abfrage |
| `Atlas.IDE.Rules` | `Atlas.IDE.Core` | Pflege der Prüfregeln: Seite „Prüfregeln“ mit Regeltabelle und Profilen, Baseline, Sammelkorrektur, Erklären, Unterdrücken am Element |
| `Atlas.IDE.Tests` | `Atlas.IDE.Core` | DUnitX-Ergebnisse und Testbefehle |
| `Atlas.IDE.Build` | `Atlas.IDE.Core` | Build-Werkzeuge: Release-Wächter, Schranke vor dem Kompilieren, Compilerschalter, Build-Zusammenfassung, „Öffnen und bauen“; Aufgaben, Startprofile |
| `Atlas.IDE.Bookmarks` | `Atlas.IDE.Core` | Lesezeichen, Notizen |

Regeln:
- Kein Modul requiret ein anderes. Querbezüge (Willkommensseite zeigt Issues, Hover zeigt Debugger-Werte, Palette öffnet die Unitsuche) laufen über Verträge im Kern; fehlt das Modul, bleibt der Beitrag leer.
- Der Kern kennt kein Modul. Module melden Einstellungsseiten, Befehle, Menüeinträge, Statusfeldzeilen, Tipps und Bereiche der Willkommensseite beim Laden an und beim Entladen ab.
- Ein nicht installiertes Modul verhält sich wie ein abgeschaltetes (Modul-Schalter aus #1454).
- Im Kern bleibt, was viele andere Teile benutzen oder ohne das Code Insight nicht brauchbar ist: die Anzeige der Diagnosen (ohne sie sähe man nicht einmal Syntaxfehler; die Prüfregeln selbst laufen im Server, ihre Pflege liegt in `Atlas.IDE.Rules`), Compilermeldungen und Prüfen nach dem Speichern (Quelle der Diagnosen), Benachrichtigungen, Rückgängig, Doku, Versionsverwaltung (Grundlage für Willkommensseite, Tracker, Tests und Änderungsmarken im Editor). Der allgemeine Tooltip `Atlas.UI.Notes.Tip` wandert vorher nach Foundation.
- Möglicher Schnitt nach dem Pilot (vermerkt, nicht entschieden): den Kern in `Atlas.IDE.Base` (Foundation, Rahmen für Einstellungen, Befehle, Statusfeld, Hosts, Style, Texte, Benachrichtigungen, Projekte, Dateien, Verträge, LSP-Client mit Serverstart erst auf Anfrage eines Moduls) und `Atlas.IDE.CodeInsight` (Vervollständigung, Hover, Signatur, Inlay-Hints, Gliederung, Anzeige der Diagnosen, Compilermeldungen, Snippets) teilen. Dann käme z. B. Bookmarks ohne Code Insight aus. Preis: zwölftes Package (48 Builds), Code Insight braucht immer zwei Installationen, und seine Beiträge an Editor, Statusfeld und Hover laufen ebenfalls über Verträge.
- Versionsverwaltung als eigenes Package ginge nur mit einer zweiten Ebene (Willkommensseite und Tracker requiren sie); vorerst nicht vorgesehen.
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
- **Entladen:** Add-ons bauen ihre Beiträge ab, bevor der Kern abgebaut wird. Einträge in den Hauptthread nur über `TAtlasMainThread` des Kerns; Editorleisten, Zeilenleisten-Spalten und Fenster nur über die Hosts des Kerns (`CLAUDE.md`).
- **Texte und Schema:** `Atlas.Core.Strings` und die erzeugte Schema-Unit werden je Package geteilt.
- **Tests:** Es bleibt ein Testprojekt `Atlas.Tests`, das alle Quellen übersetzt (kein Testprojekt je Package: Tests laden keine BPLs, und mit RAD Studio Starter wäre jedes Projekt ein eigener Lauf über `cc.ps1`). Testordner je Package (`Tests/IDE.Core`, `Tests/IDE.Debugger` …) und je Modul eine DUnitX-Kategorie, damit sich die Tests eines Moduls allein ausführen lassen. Die Prüfskripte kennen die neuen Packages.
