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

Ziel ist ein Kern-Package plus je Modul ein eigenes Design-Time-Package, das man einzeln installiert (Variante C der Analyse vom 31.10.2026):

| Package | Requires | Inhalt |
|---|---|---|
| `Atlas.IDE.Core` | rtl, vcl, vclwinx, designide | Foundation, LSP-Sitzung, Code Insight, Editor, Probleme, Gliederung, Versionsverwaltung, Rahmen für Einstellungen, Palette und Statusfeld, Verträge der Module, `Atlas.Text` als Quelltext |
| `Atlas.IDE.Debugger` | `Atlas.IDE.Core` | Debugger |
| `Atlas.IDE.Tracker` | `Atlas.IDE.Core` | Issue-Tracker und Build-Server |
| `Atlas.IDE.Welcome` | `Atlas.IDE.Core` | Willkommensseite |
| `Atlas.IDE.Analysis` | `Atlas.IDE.Core` | Architektur, Hotspots, Unit-Beziehungen, Designer |
| `Atlas.IDE.Tests` | `Atlas.IDE.Core` | DUnitX-Ergebnisse und Testbefehle |

Regeln:
- Kein Modul requiret ein anderes. Querbezüge (Willkommensseite zeigt Issues, Hover zeigt Debugger-Werte) laufen über Verträge im Kern; fehlt das Modul, bleibt der Beitrag leer.
- Der Kern kennt kein Modul. Module melden Einstellungsseiten, Befehle, Menüeinträge, Statusfeldzeilen, Tipps und Bereiche der Willkommensseite beim Laden an und beim Entladen ab.
- Ein nicht installiertes Modul verhält sich wie ein abgeschaltetes (Modul-Schalter aus #1454).
- `Atlas.Common` und `Atlas.Windows` bleiben außerhalb der IDE (ADR 0006, ADR 0012). Die Sprachlogik bleibt im Server, alle Packages nutzen die eine Sitzung des Kerns.

Reihenfolge:
1. #1454: Module als Ganzes schaltbar, weiter ein BPL.
2. #1455: Module melden sich über Verträge an; `Tools/Check-PackageDependencies.ps1` verbietet Verweise vom Kern auf Module und zwischen Modulen.
3. #1456: Kern-Package und Debugger als erstes Add-on (Pilot).
4. Die übrigen Module erst, wenn der Pilot Installieren, Entladen, Beenden und Bauen mit `cc.ps1` ohne Probleme zeigt. Zeigt er das nicht, bleibt es bei Schritt 2 und dieses ADR wird fortgeschrieben.

## Alternativen

- **Ein BPL wie bisher (Variante A):** keine Installationswahl, die Suite lädt immer ganz.
- **Ein BPL mit Modul-Schaltern (Variante B):** bekommt die Schritte 1 und 2, bleibt aber ohne Wahl bei der Installation; als Zwischenstand weiter gültig.
- **Zwei Editionen aus einer Quelle (Variante D):** „Code Insight“ und „Suite“ als zwei BPLs, von denen genau eines installiert wird. Weniger Builds als C, aber nur zwei Stufen statt einer Wahl je Modul.

## Folgen

- **Builds:** je Package Win32 und Win64 für Delphi 12 und 13; bei sechs Packages 24 statt 4 Builds je Release. `Atlas.groupproj` baut den Kern zuerst.
- **Bauen mit `cc.ps1` (ADR 0007):** Solange ein Add-on geladen ist, hält die IDE auch den Kern; zum Neubauen des Kerns werden die Add-ons mit entladen.
- **Installation (ADR 0016):** Das Release-Paket enthält Kern und Add-ons je Plattform. Der Kern wird zuerst installiert und muss für den Windows-Lader auffindbar sein, wenn ein Add-on lädt.
- **Entladen:** Add-ons bauen ihre Beiträge ab, bevor der Kern abgebaut wird. Einträge in den Hauptthread nur über `TAtlasMainThread` des Kerns; Editorleisten, Zeilenleisten-Spalten und Fenster nur über die Hosts des Kerns (`CLAUDE.md`).
- **Texte und Schema:** `Atlas.Core.Strings` und die erzeugte Schema-Unit werden je Package geteilt.
- **Tests:** `Atlas.Tests` übersetzt weiter alle Quellen; die Prüfskripte kennen die neuen Packages.
