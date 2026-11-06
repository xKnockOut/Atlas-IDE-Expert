# Handtests für Atlas 2.0.0-beta.1

Stand: 06.11.2026 (Pilot-2.0.0-beta.1 mit #1816). Sammelliste aller Handtests, die seit 1.2.0 für 2.0 dazugekommen sind (Marco, 01.11.2026: erst alles umbauen, dann eine Liste). Quellen: `docs/Atlas-Testfaelle.md`, die Sammelliste des Modulumbaus (`planung/v2/handtests-v2.md` im Projektordner), die Übergabe und die PR-Beschreibungen. Die IDs sind dieselben wie dort, damit Rückmeldungen im Issue oder PR zuzuordnen sind. Erzeugt mit `werkzeuge/handtests-v2.py` im Projektordner.

**So abarbeiten:** Teil 1 zuerst; scheitert dort etwas, lohnt der Rest nicht. Danach Teil 2: die Tests, deren Ergebnis eine offene Ursache klärt oder eine Funktion abnimmt, in der angegebenen Reihenfolge. Dann Teil 3 (Umstieg) und die übrigen Teile in beliebiger Reihenfolge. In die Spalte „Ergebnis“ ✓, ✗ mit Stichwort oder „–“ (nicht anwendbar) eintragen. Zeilen mit **Abnahme** entscheiden, ob eine Funktion als fertig gilt; sie sollten vor dem Tag `v2.0.0-beta.1` grün sein. Alle Tests in einem eigenen Registry-Profil (`bds -r Atlas20`), nicht im Standardprofil.

## Teil 1: Bauen und automatische Tests

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| B1 | Delphi 13: `Atlas.groupproj` für Win64 bauen (`pwsh Tools/Build-Test.ps1`) | 0 Fehler, 0 Warnungen, 0 Hinweise; Reihenfolge Text, Common, Windows, Server, AtlasUpdate, Base, Module, Tests (**Abnahme**) |  |
| B2 | Delphi 13: Plugin für Win32 bauen (`pwsh Tools/Build-Test.ps1 -Win32`) | 0/0/0; `Atlas.IDE.Base370.bpl` und elf `Atlas.IDE.<Modul>370.bpl` in `Output\Win32\Debug\Bpl`, keine `Atlas.IDE.Contracts370.bpl` (**Abnahme**) |  |
| B3 | `Output\Win64\Debug\Bin\Atlas.Tests.exe --exitbehavior:Continue` | Alle Tests grün, keine Leckmeldung, `TESTEXIT 0`; auch die neuen Testklassen aus den Teilen unten (UX1, ME9, LV9, DP9, UU11, AL11, ZB5, KPM11, RF10, FPR8, EK11, ENF8, BN4, LK1–LK3, HE1, SL6) (**Abnahme**) |  |
| B4 | Delphi 12 (anderer Rechner): Gruppe Win64 und Plugin Win32 bauen, Tests | 0/0/0, Tests grün (`…290.bpl`) |  |
| B5 | `pwsh Tools/Build-Referenzprojekt.ps1` | Hinweise und Warnungen genau wie in `Tests/Referenzprojekt/erwartete-meldungen.txt` |  |
| B6 | Nach B1–B3: Stand als stabil markieren | `Pilot-2.0-stable` auf diesen Commit vorrücken, Tag `delphi-ok-JJJJ-MM-TT` setzen |  |

## Teil 2: Zuerst – offene Ursachen und Abnahmen

Diese Tests zuerst, in dieser Reihenfolge. Die ersten klären eine Ursache, die aus der Cloud nicht beweisbar ist; das Ergebnis bitte im genannten Abschnitt eintragen und kurz melden. Die Zeilen selbst stehen in den Abschnitten weiter unten.

| Rang | ID | Abschnitt | Warum zuerst |
|------|----|-----------|--------------|
| 1 | KPM4 | Known Packages (Teil 5) | Klärt, ob die IDE beim Beenden ihre alte Liste zurückschreibt (Ursache (b) vom 05.11.) |
| 2 | KPM8 | Known Packages (Teil 5) | Klärt, ob das Übersetzen von Base bei installierten Modulen die Module austrägt (Ursache (a)); entscheidet, ob `cc.ps1` ein eigenes Profil braucht |
| 3 | HE3, HE4 | Hauptthread-Einträge (Teil 5) | Absturz in `MainThread` Zeile 129 beim Entladen eines Moduls (#1811) |
| 4 | RF2 | Regionen beim Öffnen (Teil 5) | Trifft „nächsten Block zuklappen“ an der Kopfzeile wirklich die Region? Sonst braucht #1814 einen anderen Weg |
| 5 | AS21, AS22 | Sitzungsmarke der Bau-IDE (Teil 5) | Bau-IDEs (`cc.ps1`) dürfen nicht als Absturz zählen; `cc.ps1` muss `ATLAS_NO_SESSION_MARKER` setzen |
| 6 | SL1, SL3 | Sprache der Serverbefunde (Teil 5) | Englische Befunde in deutscher IDE: zeigt, welche Quelle die Sprache falsch erkennt |
| 7 | FPR7 | Fehlalarme von vier Prüfregeln (Teil 5) | Klärt, ob in `RotatingFileStream` die RTL im Index fehlte oder `inline-not-expanded` RenameFile trotz Index nicht meldet |
| 8 | IT2, IT3 | Typen aus IDE-Packages (Teil 5) | Kern von #1816: keine Fehlmeldung bei Typen aus installierten Packages, aber weiter bei fehlendem uses |
| 9 | EK4 | Kontextmenü Atlas (Teil 5) | Kürzel nach dem ersten Öffnen des Menüs genau einmal (kein doppeltes Formatieren) |
| 10 | AA13, AA22 | Abgebrochene Serveranfragen (Teil 6) | Abnahme: Willkommensseite ohne Sekundentakt, kein „Absturzfall gesichert“ in sehr großen Units |
| 11 | UAL1 | Unit-Aliase (Teil 5) | Kein falsches F2613 bei `WinTypes`/`WinProcs` |
| 12 | FMK1–FMK3 | Formatieren mit Markierung (Teil 5) | Liefert die Protokollzeilen, mit denen die Ursache „Format-Knopf formatiert die ganze Unit“ gefunden wird |
| 13 | R12-1 | Korrekturen aus release/1.2 (Teil 6) | Abnahme: Strg+F unter Delphi 12 |
| 14 | UX18 | Update-Installer (Teil 6) | Abnahme: Einrichten mit `AtlasUpdate.exe install` |
| 15 | RT18 | Rauchtests (Teil 7) | Abnahme: IDE beenden ohne Zugriffsverletzung |

## Teil 3: Installation und Umstieg von 1.x

### #1456 Kern heißt Atlas.IDE.Base (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| RN1 | In der IDE (eigenes Profil) den alten Eintrag `Atlas.IDE.Expert370.bpl` aus den Known Packages entfernen, Gruppe bauen, `Output\Win32\Debug\Bpl\Atlas.IDE.Base370.bpl` installieren. | Die IDE lädt Atlas.IDE.Base; keine Meldung über ein fehlendes Atlas.IDE.Expert. |  |
| RN2 | Module bei alter, noch installierter `Atlas.IDE.Expert370.bpl` starten. | Kein Doppelstart: Module requiren Atlas.IDE.Base; die alte BPL abwählen. |  |
| RN3 | Protokoll öffnen (Atlas › Protokoll). | Die Datei heißt weiter `Atlas.IDE.Expert<Ver>.log`. |  |

### Verträge in Base, Package Atlas.IDE.Contracts entfällt

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| CB1 | Alten Eintrag `Atlas.IDE.Contracts370.bpl` aus den Known Packages des eigenen Profils entfernen und die BPL aus dem Bpl-Ordner löschen; Gruppe in Delphi 12 und 13 bauen (Win32 und Win64). | Reihenfolge Base, dann Module; keine Contracts-BPL mehr; 0 Fehler, 0 Warnungen, 0 Hinweise. |  |
| CB2 | Base und alle Module installieren, IDE neu starten. | Alles lädt ohne Meldung über ein fehlendes oder doppeltes Package; Kacheln des Trackers erscheinen auf der Willkommensseite. |  |
| CB3 | Willkommensseite: Schnellaktionen „Build“ und Tests, Einrichtung „Baseline aktualisieren“. | Funktionieren wie vorher; ist das jeweilige Modul aus, nennt die Schnellaktion den Grund. |  |
| CB4 | Programm im Debugger anhalten, Atlas › „An Issue anhängen …“. | Debug-Notiz und Exception-Verlauf werden angeboten wie vorher. |  |

### Einrichten mit AtlasUpdate

Siehe UX18 in Teil 6 (Update-Installer): `AtlasUpdate.exe install` im entpackten Release-Paket. Für den Umstieg von 1.2.0 einmal mit einem Profil prüfen, in dem 1.2.0 installiert ist.

## Teil 4: Modulumbau (#1454, #1455, #1456)

### #1454 Modulschalter (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MS1 | Optionen › Debuggen: Modulschalter „Debuggen“ aus, OK. Danach wieder an. | Visualizer, Ausnahmeleiste und Inline-Werte verschwinden ohne Neustart und kommen wieder. |  |
| MS2 | Einstellungen › Profil „Nur Code Insight“ laden. | Vervollständigung, Hover und Probleme laufen weiter; alle Modulschalter stehen auf aus. |  |
| MS3 | Modul Prüfregeln aus; Projekt öffnen, dessen atlas.json `rules` oder `profile` setzt. | Hinweis „Prüfregeln sind aus“ genau einmal; „Prüfregeln einschalten“ schaltet ein, Befunde erscheinen. |  |
| MS4 | Modul Suche aus. | „Units suchen“ und „Suchen“ fehlen in Menü und Palette. |  |

### #1455 Debugger meldet sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MV1 | IDE starten, Atlas-Protokoll öffnen. | Kein Eintrag „Vertragsversion von Base passt nicht“; im Diagnosefenster erscheint das Modul `atlas.debugger` mit allen Teilen (DebugCommands, Visualizers, DisplayRules, Debug*). |  |
| MV2 | Befehlspalette öffnen, „Auswerten“, „Exception-Verlauf“, „Schrittfilter“, „Nur eigener Code“ suchen. | Alle Debugger-Befehle stehen in der Palette und laufen; ausgeschaltete Funktionen (z. B. debug.exceptionHistory aus) fehlen. |  |
| MV3 | Atlas-Menü öffnen. | „Exception-Verlauf“ und „Auswerten“ stehen an derselben Stelle wie in 1.2; mit dem Modulschalter „Debuggen“ aus fehlen sie. |  |
| MV4 | Im Editor Rechtsklick › Atlas. | „Gezielt hineinspringen“ (mit Tastenkürzel), „Routine überspringen“ und „Nicht mehr überspringen“ stehen im Untermenü und laufen. Mit debug.stepIntoTarget aus fehlt „Gezielt hineinspringen“ (neu: vorher sichtbar mit Hinweis). |  |
| MV5 | Programm anhalten, Taste von „Gezielt hineinspringen“ drücken; dann ohne laufendes Programm drücken. | Angehalten: Liste der Aufrufe. Ohne Programm: Taste geht an die IDE weiter. |  |
| MV6 | Liste „Gezielt hineinspringen“ offen, anderen Editorreiter wählen. | Liste schließt sich. |  |
| MV7 | Angehalten über einer TStringList-Variablen den Hover öffnen. | Visualisierter Wert wie in 1.2 (Typ kommt jetzt aus dem Hover selbst). |  |
| MV8 | Optionen › Debuggen ändern (z. B. Exception-Leiste aus), OK; Thema hell/dunkel wechseln. | Änderungen wirken ohne Neustart; Fenster Auswerten, Exception-Verlauf, Schrittfilter folgen dem Thema. |  |
| MV9 | Angehalten: Tracker › „An Issue anhängen …“. | Debug-Notiz, Exception-Verlauf und Fenster des Prozesses stehen zur Auswahl wie in 1.2; Dateiname `debug-notiz-…md`. Mit Modulschalter „Debuggen“ aus: Debug-Notiz wie in 1.2, Exception-Verlauf leer; der Dialog läuft. |  |
| MV10 | Modulschalter „Debuggen“ aus, OK, wieder an. | Alle Debugger-Teile stoppen und starten ohne Neustart, F7 verhält sich danach wie ohne Atlas bzw. mit Schrittfilter. |  |
| MV11 | IDE beenden mit laufender Debug-Sitzung. | Keine Zugriffsverletzung; Protokoll ohne „nicht sauber abgemeldet“. |  |

### #1455 Lesezeichen melden sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| ML1 | IDE starten, Diagnosefenster öffnen. | Modul `atlas.bookmarks` mit den Teilen Notes, Bookmarks, QuickBookmarks; kein Eintrag „Vertragsversion passt nicht“. |  |
| ML2 | Atlas-Menü › „Notizen und Lesezeichen“ öffnen; dann notes.enabled aus, bookmarks.quick aus. | Einträge wie in 1.2 (Notizen, Trennlinie, Lesezeichen, schnelle Lesezeichen); ausgeschaltete fehlen ohne doppelte oder überzählige Trennlinie; alles aus = Untermenü fehlt. |  |
| ML3 | Im Editor Rechtsklick › Atlas, auch nach Rechtsklick in die Rinne. | Notiz hinzufügen/löschen/Liste, Lesezeichen setzen (mit Strg+Alt+K), Gehe zu, schnelles Lesezeichen; gelten für die angeklickte Zeile. |  |
| ML4 | Strg+Alt+K, Strg+Umschalt+1…9, Strg+1…9, Strg+Umschalt+K (Akkord), nächstes/voriges Lesezeichen. | Wie in 1.2; mit Wartezeit 0 bleibt Strg+Umschalt+K bei der IDE; mit bookmarks.quick aus gehören alle Tasten der IDE. |  |
| ML5 | Notizen › Liste im Ergebnisfenster; Eintrag doppelklicken, Kontextmenü „Bearbeiten“/„Löschen“, Entf-Taste. | Liste nach Unit gruppiert, Sprung, Bearbeiten und Löschen wie in 1.2. |  |
| ML6 | Rinne: Notiz und Lesezeichen an einer Zeile, darüber fahren. | Beide Symbole links von den Rekursionssymbolen, Tooltip mit Titel wie in 1.2. |  |
| ML7 | Übersichtsleiste mit Art „bookmarks“ und schnellen Lesezeichen. | Lesezeichen von Atlas als Marken; mit bookmarks.quick aus die IDE-Lesezeichen 0–9. |  |
| ML8 | Palette: „TODO-Liste“ und „TODO-Liste filtern …“; während eines Builds noch einmal. | Liste im Ergebnisfenster; Filter wirkt; während eines laufenden Hintergrundbefehls Hinweis „später noch einmal“. |  |
| ML9 | Modulschalter „Lesezeichen“ aus, OK, wieder an. | Befehle, Menüeinträge, Tasten, Symbole in Rinne und Übersichtsleiste, Feld im Statusfeld verschwinden ohne Neustart und kommen wieder. |  |
| ML10 | Modulschalter „Debuggen“ aus. | Debugger-Befehle fehlen jetzt auch in Palette, Atlas-Menü und Kontextmenü (Ursache behoben: gestoppte Module trugen noch bei). |  |
| ML11 | TODO-Liste anstoßen und sofort IDE beenden. | Keine Zugriffsverletzung; die späte Antwort des Servers wird verworfen. |  |

### #1455 Build-Werkzeuge melden sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MB1 | Diagnosefenster öffnen. | Modul `atlas.build` mit den Teilen OpenBuild, Tasks, StartProfiles, CompilerSwitches. |  |
| MB2 | Atlas-Menü öffnen (Projekt mit Aufgaben in atlas.json, dann ohne Aufgaben, dann tasks.enabled aus). | „Compiler-Schalter“ und Untermenü „Aufgaben“ stehen jetzt bei den Einträgen der Module (neue Stelle); je Aufgabe ein Eintrag mit letztem Lauf und Taste, Klick startet sie; ohne Aufgaben ein ausgegrauter Eintrag; mit tasks.enabled aus fehlt das Untermenü. |  |
| MB3 | Palette: „Aufgabe ausführen …“, „Alle Prüfungen“, „Letzte wiederholen“, „Abbrechen“, „Ausgabe umschalten“, „Befunde je Aufgabe“, „Startprofil …“, „Compiler-Schalter“. | Alle laufen wie in 1.2. |  |
| MB4 | tasks.beforeBuild = block, eine Prüfung schlägt fehl, Build starten. | Build bricht ab mit Meldung, nach bestandener Prüfung baut Atlas neu (über den Läufer von Base). |  |
| MB5 | Willkommensseite › Projekte: „Aufgaben ▾“ und „Start ▾“ (Startprofile). | Namen erscheinen, Start läuft, das Ergebnis steht nach dem Ende in der Zeile. |  |
| MB6 | build.onOpen an, Projektgruppe öffnen; Modulschalter „Build-Werkzeuge“ aus, OK, wieder an. | Bauen beim Öffnen wie in 1.2; aus = Einträge, Felder im Statusfeld (Startprofil, Schalter) und Aufgaben verschwinden ohne Neustart, Release-Wächter und Prüfung vor dem Kompilieren laufen weiter; an = alles kommt wieder. |  |
| MB7 | Modulschalter mehrmals aus und an, dann Build starten. | Kein doppelter Ablauf der Aufgaben vor dem Build (Teilnehmer wird beim Stoppen abgemeldet). |  |
| MB8 | IDE beenden, während eine Aufgabe läuft. | Keine Zugriffsverletzung. |  |

### #1455 Tests melden sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MT1 | Diagnosefenster öffnen. | Modul `atlas.tests` mit dem Teil Tests. |  |
| MT2 | Palette: „Tests ausführen“, „Fehlgeschlagene erneut ausführen“, „Test am Cursor ausführen“, „Test am Cursor debuggen“, „Betroffene Tests ausführen“. | Alle laufen wie in 1.2; „Fehlgeschlagene“ kennt nach einem IDE-Neustart die Tests des letzten Laufs, auch mit ausgeschalteter Willkommensseite. |  |
| MT3 | Im Editor einer Testunit Rechtsklick › Atlas. | „Test ausführen“ und „Test debuggen“ stehen im Untermenü (neu: kommen aus dem Modul); mit tests.run aus fehlen beide, mit „Test debuggen“ aus fehlt nur der zweite (vorher sichtbar mit Hinweis). |  |
| MT4 | Atlas-Menü öffnen. | „Betroffene Tests ausführen“ steht jetzt bei den Einträgen der Module (neue Stelle); mit tests.affected aus fehlt er. |  |
| MT5 | tests.afterBuild an, Projekt bauen (mit Warnung und build.zeroHints an, dann ohne). | Tests laufen nur nach einem Build, der als erfolgreich gilt, wie in 1.2. |  |
| MT6 | Test am Cursor debuggen, mit und ohne Startprofil, Modul „Build-Werkzeuge“ aus. | Debuggen läuft auch ohne das Modul Build; danach stehen die Startparameter wie vorher, ein aktives Startprofil gilt spätestens nach einer Sekunde wieder. |  |
| MT7 | Willkommensseite: Karte Tests „Fehlgeschlagene erneut ausführen“, „Im Debugger“, Sprung zum Test; Schnellaktion „Tests“. | Wie in 1.2; das Ergebnis steht nach dem Lauf in Karte und Zeile. Mit Modulschalter „Tests“ aus: Hinweis „Tests sind aus“. |  |
| MT8 | Auswirkungen anzeigen › „Betroffene Tests ausführen“, einmal mit Modul Tests an, einmal aus. | An: die Tests laufen. Aus: Hinweis „Tests sind aus“. |  |
| MT9 | tests.affectedBeforeCommit an, dann Modulschalter „Tests“ aus. | Der pre-commit-Hook entsteht bzw. wird beim Ausschalten entfernt. |  |
| MT10 | Modulschalter „Tests“ aus, OK, wieder an; IDE beenden während eines Testlaufs. | Lens, Befehle, Einträge und Probleme der Tests verschwinden ohne Neustart und kommen wieder; beim Beenden keine Zugriffsverletzung. |  |

### #1455 Designer meldet sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MD1 | Diagnosefenster öffnen. | Modul `atlas.designer` mit dem Teil DesignerBar. |  |
| MD2 | Formular im Designer öffnen; Suche, Tab-Reihenfolge, Ausrichten der Leiste nutzen; Thema wechseln. | Leiste wie in 1.2, folgt dem Thema. |  |
| MD3 | editor.designerBar aus, OK, wieder an; dann Modulschalter „Designer“ aus und an. | Leiste verschwindet ohne Neustart und kommt wieder; die Meldungen beim Speichern eines Formulars (Teil Forms) laufen weiter. |  |
| MD4 | Abgesicherter Start (Stufe Safe), Formular öffnen. | Leiste erscheint wie in 1.2. |  |

### #1455 Suche meldet sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MF1 | Diagnosefenster öffnen. | Modul `atlas.search` mit den Teilen Search, UnitSearch, Query. |  |
| MF2 | Strg+F, Strg+H (mit search.replace), F3/Umschalt+F3 nach einer Suche, „In Methode suchen“. | Wie in 1.2. |  |
| MF3 | Ohne Atlas-Suche: F3 auf einer Austrittspunkt-Hervorhebung, F3 mit einzeiliger Markierung, F3 ohne beides; dann Modulschalter „Suche“ aus und dasselbe. | Austrittspunkte, Markierung suchen, „Erneut suchen“ der IDE wie in 1.2, auch mit der Suche aus. |  |
| MF4 | Strg+F12, Alt+F11, Umschalt+F12; Palette „Units suchen“, „Unit verwenden“, „Formulare“ und die IDE-Dialoge. | Wie in 1.2. |  |
| MF5 | Atlas-Menü öffnen. | „Units suchen“, „IDE-Dialog Units“ und „Atlas-Abfrage“ stehen jetzt bei den Einträgen der Module (neue Stelle); mit query.enabled aus fehlt die Abfrage. |  |
| MF6 | Ansicht › Atlas öffnen (query.enabled an, dann aus). | „Atlas-Abfrage“ steht unten im Untermenü (neue Stelle); aus = fehlt; ist sonst nichts sichtbar, fehlt Ansicht › Atlas. |  |
| MF7 | Atlas-Abfrage: Abfrage ausführen, Vorschläge beim Tippen, Modulschalter „Suche“ aus während einer langen Abfrage. | Ergebnis wie in 1.2; nach dem Ausschalten kommt keine Antwort mehr an, keine Zugriffsverletzung. |  |
| MF8 | Tastenkürzel-Übersicht mit unitSearch.replaceIdeDialog an und aus. | Strg+F12 erscheint als Atlas-Zeile bzw. als Aktion der IDE wie in 1.2. |  |
| MF9 | Modulschalter „Suche“ aus, OK, wieder an. | Befehle, Einträge, Tasten und Suchleiste verschwinden ohne Neustart und kommen wieder; Strg+F12 gehört ausgeschaltet der IDE. |  |

### #1455 Analyse meldet sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MA1 | Diagnosefenster öffnen. | Modul `atlas.analysis` mit den Teilen Architecture, UnitRelations, Hotspots, SymbolPath. |  |
| MA2 | Atlas-Menü öffnen. | Architektur, Hotspots, Unit-Beziehungen und „Weg zwischen Symbolen“ stehen jetzt bei den Einträgen der Module (neue Stelle); mit architecture.enabled, hotspots.enabled bzw. navigation.symbolPath aus fehlen sie. |  |
| MA3 | Ansicht › Atlas öffnen. | Architektur, Hotspots, Unit-Beziehungen mit den Texten wie in 1.2, unten im Untermenü (neue Stelle). |  |
| MA4 | Architekturfenster öffnen, Karte laden, Strg+Doppelklick auf eine Unit; Palette „Teuerste Units“. | Wie in 1.2; Strg+Doppelklick öffnet die Unit-Beziehungen der Unit. |  |
| MA5 | Unit-Beziehungen offen lassen und gleichzeitig das Architekturfenster laden. | Beide laden; keins wartet auf das andere. |  |
| MA6 | Im interface-Teil einer Unit tippen. | Feld „interface-Änderung: N Units …“ im Atlas-Statusfeld wie in 1.2; Klick zeigt die Abhängigkeiten. Modulschalter „Analyse“ aus: Feld verschwindet sofort. |  |
| MA7 | Hotspots-Fenster öffnen (ohne laufenden Server), „Auswirkungen anzeigen“. | Server startet, Hotspots laden; Auswirkungen wie in 1.2. |  |
| MA8 | Kontextmenü im Editor auf einem Symbol › Atlas › „Weg von hier nach …“; Weg suchen, „In Architekturkarte zeigen“. | Dialog mit „Von“ vorbelegt (neue Stelle im Kontextmenü, bei den Einträgen der Module); Weg im Ergebnisfenster, Karte zeigt ihn. |  |
| MA9 | Unit-Zyklus erzeugen; im Tooltip „Graph zeigen“ und die Code-Aktion „Graph zeigen“. | Unit-Beziehungen der Unit im Editor; mit Modulschalter „Analyse“ aus passiert nichts (kein Fehler). |  |
| MA10 | Modulschalter „Analyse“ aus, OK, wieder an; Thema wechseln. | Fenster, Befehle, Einträge verschwinden ohne Neustart und kommen wieder; Fenster folgen dem Thema. |  |

### #1455 Prüfregeln melden sich als Modul an (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MR1 | Diagnosefenster öffnen. | Modul `atlas.rules` ohne Teile (nur Beiträge). |  |
| MR2 | Palette: „Baseline des Projekts aktualisieren“ mit Einträgen ohne Datei. | Rückfrage mit den Pfaden, danach Zähler in der Meldungsansicht wie in 1.2; Projektverlauf zeigt den neuen Stand. |  |
| MR3 | Projekt bauen mit Warnungen, Palette „Aktuelle Compilermeldungen in die Basislinie“. | Zähler in der Meldungsansicht wie in 1.2. |  |
| MR4 | Palette „Eigenschaftsregeln anwenden“ (Formular, Projekt, Gruppe). | Vorschau und Übernahme wie in 1.2. |  |
| MR5 | „Atlas-Prüfung“: Kontextmenü auf einem Befund „Alle sicheren Treffer … korrigieren …“. | Vorschau, Übernahme, Zeile in der Meldungsansicht wie in 1.2; mit fix.bulk aus fehlt der Eintrag. |  |
| MR6 | Willkommensseite › Projekt einrichten › Baseline anlegen. | Läuft wie in 1.2; mit Modulschalter „Prüfregeln“ aus kommt „Das Modul Prüfregeln ist ausgeschaltet …“ (neu). |  |
| MR7 | Modulschalter „Prüfregeln“ aus, OK. | Befehle und Sammelkorrektur verschwinden ohne Neustart; Fenster „Atlas-Prüfung“, Erklären, Unterdrücken, Abschalten laufen weiter; Hinweis „Prüfregeln einschalten“ wie in 1.2. Wieder an: alles zurück. |  |
| MR8 | Lange Sammelkorrektur starten, währenddessen Modulschalter „Prüfregeln“ aus. | Keine Vorschau mehr, keine Zugriffsverletzung. |  |

### #1455 Texte und Testkategorien je Modul (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MX1 | IDE auf Englisch und auf Deutsch starten; je Modul einen Befehl in der Palette, einen Dialog (Lesezeichen, Debugger „Auswerten“, Suche, Architektur, Startprofile, Tests ausführen, Eigenschaftsregeln, Designer-Suche) öffnen. | Alle Texte in der Sprache der IDE wie in 1.2, kein leerer Text, keine Platzhalter wie `%s` sichtbar. |  |
| MX2 | `Atlas.Tests.exe --include:Atlas.IDE.Debugger` (bzw. `-i:`). | Es laufen nur die Tests des Debuggers (rund 25 Testklassen), alle grün. |  |
| MX3 | `Atlas.Tests.exe --exclude:Atlas.IDE.Tracker,Atlas.IDE.Welcome`. | Tracker- und Willkommenstests fehlen, der Rest läuft grün. |  |

### #1455 Build-Pipeline als eigenes Modul (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| BP1 | Optionen › Atlas › Release-Build: Modulschalter „Build-Pipeline“ sichtbar und an. Release-Konfiguration mit DEBUG-Symbol bauen. | Befund `[release-debug-define]` in der Atlas-Gruppe des Meldungsfensters wie in 1.2; mit build.gate = block bricht der Build ab. |  |
| BP2 | Modulschalter „Build-Pipeline“ aus, ohne Neustart; Release-Build wie BP1, dann Befehlspalette. | Kein Befund, kein Abbruch; „Release-Build prüfen“ fehlt in der Palette. Benachrichtigung „Build fertig“ kommt trotzdem; Tests nach dem Build laufen weiter (nur nach dem Compiler bewertet, Hinweise halten nicht an). |  |
| BP3 | Schalter wieder an; build.gate = warn, eine Unit mit Fehler ändern, bauen. | Prüfung vor dem Kompilieren meldet den Fehler in der Atlas-Gruppe; Build läuft weiter. |  |
| BP4 | Claude Code: `build_project` auf ein offenes Projekt (McpBuild an); dann Modul aus und erneut. | Erst Ergebnis mit Meldungen wie in 1.2; mit Modul aus Antwort „nicht gebaut“ bzw. Zeitüberschreitung, kein Absturz, keine Datei bleibt im Eingang hängen. |  |
| BP5 | Willkommensseite: Schnellaktion „Bauen“; Projektaufgabe mit Neubau nach der Prüfung (Modul Build-Werkzeuge). | Beide bauen über das Modul; mit Modul aus Grund „kein Build-Läufer“ statt Build. |  |
| BP6 | build.zeroHints an, Build mit einem Hinweis, Zusammenfassung an; danach `Atlas.CompilerBaseline`. | Zusammenfassung „abgelehnt“ wie in 1.2; Compilermeldungen landen in der Baseline (Meldungen des letzten Builds aus Base), auch wenn das Modul zwischendurch aus- und angeschaltet wurde. |  |
| BP7 | IDE beenden während eines Builds auf Auftrag. | Kein Fehler beim Entladen; Auftraggeber bekommt „Atlas wurde in der IDE beendet“. |  |

### #1455 Willkommensseite als eigenes Modul (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| WM1 | IDE starten (normal und abgesichert). | Willkommensseite bzw. „Atlas-Start“ wie in 1.2 mit allen Bereichen; im Optionsdialog Modulschalter „Willkommensseite“ an. |  |
| WM2 | Atlas-Menü und Ansicht › Atlas öffnen, mit welcomePage.ideWelcomePage an und Layout aus, dann Layout „atlas“. | „Atlas-Start“, „Atlas-Layout anwenden“ bzw. „zurücksetzen“ stehen jetzt bei den Einträgen der Module (mit Trennlinie), „Atlas-Start“ unter Ansicht › Atlas statt direkt unter Ansicht. Anwenden nur ohne, Zurücksetzen nur mit Atlas-Layout; Wirkung wie in 1.2. |  |
| WM3 | welcomePage.enabled aus; Atlas-Menü und Palette. | Einträge und Befehle der Seite (Start, Anwenden, Zurücksetzen, Neu in Atlas) ausgeblendet, auch in der Palette. |  |
| WM4 | Palette: Seite anpassen, Neu in Atlas (aktuell/alle), Projekt für Atlas einrichten, Weiterarbeiten, Zugang zum Build-Server. | Jeweils wie in 1.2; „Zugang zum Build-Server“ nur mit ci.login und Bereich „Testergebnisse“. |  |
| WM5 | Schnellaktionen: Bauen, Tests, Startprofil, Aufgaben ▾; Einrichtung: Baseline, „Neu mit Atlas“. | Wie in 1.2; Module Build-Pipeline, Tests, Build bzw. Prüfregeln aus: Grund statt Aktion, keine Fehlermeldung. |  |
| WM6 | Modulschalter „Willkommensseite“ aus, OK; wieder an. | Seite und „Atlas-Start“ schließen ohne Neustart, Befehle und Menüeinträge verschwinden; nach dem Einschalten wieder da. Keine Zugriffsverletzung, Atlas-Layout der IDE bleibt bzw. lässt sich zurücksetzen. |  |
| WM7 | Thema wechseln (hell/dunkel) bei offener Seite; eine Einstellung der Seite ändern. | Seite folgt dem Thema und der Einstellung sofort. |  |
| WM8 | IDE beenden mit offener Seite und laufender Abfrage (Projekte, Nicht gesichert). | Kein Fehler beim Entladen. |  |

### #1455 Projekt-Zusammenfassungen in Base (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| PS1 | Willkommensseite aus (welcomePage.enabled), Projekt öffnen, bauen, schließen; Willkommensseite wieder an. | Bereich „Projekte“ zeigt den letzten Build, Branch und Regeltreffer dieses Laufs (neu: auch ohne Willkommensseite geschrieben). |  |
| PS2 | Projekt bauen mit welcomePage.trends an. | Projektverlauf bekommt einen Messpunkt mit Metriken, TODOs, Baseline, Branch und Commit wie in 1.2. |  |
| PS3 | Testprojekt über Schnellaktion „Tests“ ausführen; danach Modulschalter „Tests“ aus und wieder an. | Zeile zeigt bestanden/fehlgeschlagen, Karte Tests den Lauf wie in 1.2; kein Fehler beim Umschalten. |  |
| PS4 | „Baseline des Projekts aktualisieren“ (Modul Prüfregeln), danach Projektverlauf. | Abschnitt Baseline mit den Zählern des Servers wie in 1.2; Release-Wächter liest weiter `%LOCALAPPDATA%\Atlas\projects`. |  |

### #1455 Modulgrenzen im Prüfskript (Paket 1)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MG1 | Unter Windows: `pwsh Tools/Check-PackageDependencies.ps1` und `powershell -File Tools/Check-PackageDependencies.ps1` (Windows PowerShell 5.1). | Beide grün; gelbe Liste „Bekannte Verstöße gegen die Modulgrenzen (92 …)“, Umlaute lesbar. |  |
| MG2 | Unter Windows: `pwsh Tools/Test-PackageDependencies.ps1`. | Elf Zeilen „ok: …“, am Ende „Modulgrenzen: alle Fälle wie erwartet.“; kein temporärer Ordner `atlas-modules-*` bleibt zurück. |  |

### #1455 Tracker meldet sich als Modul an (Paket 2, PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MK1 | Diagnosefenster öffnen. | Modul `atlas.tracker` mit Teilen IssueLinks und BlameIssues (laufen, sobald „Meine Issues“ läuft; nicht in der Stufe Minimal). |  |
| MK2 | Projekt mit Tracker in der .atlas; im Code `ATL-123` bzw. `#753` schreiben, darauf zeigen und klicken. | Unterstreichung, Tooltip, Vorschau bzw. Browser, „Beginnen“ im Kontext wie in 1.2. |  |
| MK3 | Mit editor.gitBlame und issues.blameLinks auf einer Zeile mit Commit „ATL-97 …“; Palette „Issues zu dieser Methode“. | Randanzeige mit Issue wie in 1.2; Liste der Issues der Methode (Rumpf um den Cursor), außerhalb einer Methode der ganzen Unit. |  |
| MK4 | Palette: Zugang zum Issue-Tracker, Zugang zum Build-Server, Issue anzeigen, offene Zeitbuchungen, Board, An Issue anhängen. | Jeweils wie in 1.2; jeder nur sichtbar mit seiner Einstellung. |  |
| MK5 | Atlas-Menü „An Issue anhängen …“, Ansicht › Atlas › Board. | Beide jetzt bei den Einträgen der Module (Board unten unter Ansicht › Atlas); Wirkung wie in 1.2. |  |
| MK6 | Text markieren, Kontextmenü › „Issue anlegen …“; Taste keys.createIssue belegen und drücken. | Dialog „Issue anlegen“ wie in 1.2 (Eintrag jetzt bei den Einträgen der Module). |  |
| MK7 | Modulschalter „Issue-Tracker und Build-Server“ aus, OK; wieder an. | Kennungen, Randanzeige, Befehle, Menü- und Kontextmenüeinträge, Taste verschwinden ohne Neustart und kommen wieder; keine Zugriffsverletzung. |  |
| MK8 | welcomePage.enabled aus (Willkommensseite aus), dann Palette. | Tracker-Befehle unsichtbar, Kennungen im Code ohne Wirkung, keine Fehlermeldung. |  |
| MK9 | „Branch anlegen“ (#1288) mit ungültigem Namen „a..b“ und ohne vcs.projects. | Hinweis und gesperrtes „Anlegen“ wie in 1.2; Basis main/master bzw. trunk vorgeschlagen. |  |
| MK10 | Lesezeichen in einer Methode setzen, Methode verschieben; „Weiterarbeiten“ zeigt die Methode der letzten Änderung. | Lesezeichen folgt der Methode, Methode in „Weiterarbeiten“ wie in 1.2. |  |

#### Seite Issue-Tracker als Abschnitt des Moduls (Paket 2, PR #1468)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MK11 | Tools › Optionen › Atlas › Issue-Tracker öffnen. | Reihenfolge wie in 1.2: Verbindungen, Projekte, Abfragen (mit Klappliste und „Issue anlegen“), Anbieter bis Kommentar-Editor, Zustand im Tracker, Zeiterfassung, Textbausteine, Checklisten bis Anhängen. Punkt, Zurücksetzen und Sperre durch Hauptschalter an jeder Zeile. |  |
| MK12 | Verbindung hinzufügen, Name, Anbieter YouTrack, Adresse `http://…` eingeben; dann `https://…`. | Bei http roter Hinweis, Zeile wird nicht übernommen; mit https wird sie übernommen. Bei GitHub sind Zustandsfeld und Benutzerfeld ausgeblendet. |  |
| MK13 | „Token hinterlegen …“, dann „Verbindung prüfen“. | Verdeckter Dialog; Zustand wechselt auf „wird geprüft“ und dann „geprüft hh:mm“; bei deutscher YouTrack-Oberfläche wird die Sprache gemerkt (nach OK in issues.connections). |  |
| MK14 | Verbindung umbenennen, die in Projekten und Abfragen verwendet wird. | Projekte und Abfragen zeigen den neuen Namen, nach OK auch gespeichert. |  |
| MK15 | Projekte: „Aktuelles Projekt hinzufügen“, „Hinzufügen …“ (Datei und Ordner), Zeile aus der .atlas. | Zeilen wie in 1.2; Zeile aus der .atlas grau und nicht bearbeitbar; überdeckte Zeilen mit Hinweis. |  |
| MK16 | In „Meine Issues“ „Kein Tracker für dieses Projekt – zuordnen …“. | Optionsdialog springt auf Projekte, neue Zeile für das Projekt gewählt, Fokus im Feld Tracker-Projekt. |  |
| MK17 | Abfragen: hinzufügen, „Bearbeiten …“, Vorlage einsetzen, „Testen“, OK. | Dialog wie in 1.2, Ergebnis mit Ursache; Name doppelt sperrt OK. |  |
| MK18 | Zustand im Tracker: „Werte vom Tracker laden“. | Knopf gesperrt mit „Lade …“, danach Klapplisten global und an der Verbindung gefüllt, Anzahl im Hinweis; Fehler nennt den Grund. |  |
| MK19 | Textbausteine: hinzufügen (bis zur Höchstzahl), Text mit Zeilenumbruch, entfernen, „Vorgaben“. | Tabelle zeigt Umbrüche als ⏎; „Hinzufügen“ bei Höchstzahl gesperrt; nach OK in issues.commentSnippets. |  |
| MK20 | Muster des Commits `{kennung} ` mit Leerzeichen am Ende, Kommentare beim Beginnen mit Leerraum, Zielzustände `Fertig,  Erledigt`; OK, Seite neu öffnen. | Muster und Kommentare ungekürzt, Zielzustände als `Fertig, Erledigt`. |  |
| MK21 | Seite schließen, während „Verbindung prüfen“ bzw. „Werte laden“ läuft; IDE schließen während einer Prüfung. | Keine Zugriffsverletzung, späte Antwort verfällt. |  |
| MK22 | Modulschalter „Issue-Tracker“ aus, Optionsdialog öffnen, OK; wieder an. | Seite ohne Abschnitt des Trackers; die Werte (Verbindungen, Abfragen …) bleiben erhalten und sind nach dem Einschalten wieder da. |  |

#### Kacheln des Trackers

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| MK23 | Willkommensseite öffnen (welcomePage.issues und welcomePage.sprint an), Projekt mit Tracker wählen. | Kacheln „Meine Issues · Projekt“ und Sprint an ihrem Platz wie in 1.2 (Reihenfolge 26 bzw. 27, Layouts bleiben); Liste lädt, „Stand vom …“ ohne Netz. |  |
| MK24 | Dasselbe im Fenster „Atlas-Start“ (Ansicht › Atlas). | Beide Kacheln auch dort, gleicher Inhalt; Wechsel des Projekts zieht den Titel nach. |  |
| MK25 | Abfrage-Klappliste (issues.queryPicker an) in der ersten Zeile der Kachel; andere Abfrage wählen; „Abfragen bearbeiten …“. | Klappliste mit Trefferzahlen, Wechsel fragt sofort ab; „Abfragen bearbeiten …“ öffnet die Seite Issue-Tracker bei Abfragen. |  |
| MK26 | Rechtsklick auf eine Zeile: Beginnen, Im Browser, Pull Request, Vorschau; Strg+Klick auf die Kennung. | Kontextmenü wie in 1.2; Strg+Klick öffnet den Browser, Klick die Vorschau „Atlas-Issue“ (mit Punkt am ersten neuen Kommentar). |  |
| MK27 | „Beginnen“ in einem Git-Projekt ohne den Branch, mit vcs.branch.confirm an; dann einmal aus mit uncommitted = ask und lokalen Änderungen. | Dialog „Branch anlegen“ bzw. Frage „Mitnehmen / Beiseitelegen / Abbrechen“; danach Hinweis „Branch … angelegt“, Statusfeld „Issue: ATL-… Titel“, Projekt offen. Abbrechen ändert nichts. |  |
| MK28 | Issue mit offenem „hängt ab von“ beginnen (issues.warnBlocked an): „ATL-… ansehen“, dann „Trotzdem beginnen“. | Erst die Vorschau des blockierenden Issues ohne Beginnen; dann Beginnen wie MK27. |  |
| MK29 | Statusfeld: Klick auf „Issue: …“, Checkliste und „Anhängen …“; Commit-Dialog der IDE öffnen. | Beenden-Dialog bzw. Rückfrage; Checkliste in der Vorschau; Dialog „An Issue anhängen“; Präfix vorn im Nachrichtenfeld, einmal je Dialog. |  |
| MK30 | Sprint-Kachel: „meine offen“ / „meine erledigt“, „alle zeigen“, Board-Link; welcomePage.issues aus und erneut „meine offen“. | Liste gefiltert mit „Gefiltert: …“, „alle zeigen“ hebt auf; ohne den Bereich öffnet der Klick das Board. Burndown und Vergleich wie in 1.2. |  |
| MK31 | Kontextmenü im Editor › „Issue anlegen …“ auf einer TODO-Zeile; „gleich beginnen“ an; danach aus „Atlas-Prüfung“ für zwei Befunde. | Dialog wie in 1.2, TODO bekommt die Kennung, Kennung in der Zwischenablage, Beginnen startet; aus Befunden ein Issue mit Liste, Code unverändert. |  |
| MK32 | Modul Willkommensseite aus (welcome), Tracker an. | Keine Kacheln, keine Fehlermeldung; Statusfeld, Befehle (Issue anzeigen, Board, Anhängen, Zugang hinterlegen) und „Issue anlegen“ laufen weiter. |  |
| MK33 | Modulschalter „Issue-Tracker“ aus und wieder an, während eine Abfrage bzw. ein „Beginnen“ läuft; danach IDE schließen. | Kacheln verschwinden und kommen wieder, keine Zugriffsverletzung, späte Antworten verfallen; beim Schließen keine AV (#1233). |  |
| MK34 | Palette: „Zugang zum Issue-Tracker hinterlegen“ und auf der Kachel „Zugang hinterlegen“; „Zugang zum Build-Server“ (seit Paket 2c wieder im Modul Tracker, siehe MK38). | Zugangsdialog für den Tracker des aktiven Projekts bzw. des Bereichs, danach sofortige Abfrage; Build-Server-Zugang wie in 1.2. |  |
| MK35 | Willkommensseite mit Projekten mit lokalem Testlauf und mit Build-Server (.atlas, Jenkins); Kachel „Testergebnisse“ ansehen, gespeichertes Layout von 1.2. | Kachel an alter Stelle (linke Spalte, nach „Projektverlauf“), Zeilen, Ampeln, Marken und Fehlschläge wie in 1.2; einmal abgefragt beim Anzeigen. |  |
| MK36 | In der Kachel einen Fehlschlag doppelklicken (lokal und nur vom Server), „Fehlgeschlagene erneut ausführen“, „Im Debugger“, „Im Browser“. | Projekt öffnet, Test springt an Datei und Zeile; Lauf startet genau diese Tests; Debugger startet den Test; Browser öffnet die Seite des Builds. |  |
| MK37 | Modul Tests aus, in der Kachel „Fehlgeschlagene erneut ausführen“ und „Im Debugger“. | Meldung „Tests sind aus“ bzw. nichts, keine Fehlermeldung. |  |
| MK38 | Palette „Zugang zum Build-Server hinterlegen …“ (jetzt Modul Tracker) und Kontextmenü der Kachel › Zugang; beide Felder leer bestätigen. | Dialog mit Benutzer vorbelegt, Token verdeckt; danach sofortige Abfrage; leer entfernt den Zugang mit Meldung in der Meldungsansicht. |  |
| MK39 | Build wird rot (voriger grün), welcomePage.tests.ci.notify an. | Hinweis in der Benachrichtigungszentrale mit „Im Browser“ wie in 1.2. |  |
| MK40 | Testlauf aus der IDE beenden, Branch wechseln. | Kachel liest sofort neu (Zusammenfassung von Base), ohne Neustart. |  |
| MK41 | Modulschalter „Issue-Tracker und Build-Server“ aus, während eine Abfrage beim Build-Server läuft; wieder an; IDE schließen. | Kachel verschwindet und kommt wieder, Palette ohne „Zugang zum Build-Server“, keine AV, beim Schließen keine AV (#1233). |  |
| MK42 | Optionsdialog › Issue-Tracker bei ausgeschaltetem Modul: Token hinterlegen, „Verbindung prüfen“. | Abschnitt bedienbar, Token gespeichert, Prüfung läuft (Zugang kommt jetzt aus dem Modul, nicht aus der Wurzel). |  |
| MK43 | Fenster „Atlas-Prüfung“: zwei Befunde › „Für diesen Befund ein Issue anlegen …“; einmal mit Modul Tracker aus. | Dialog mit Liste wie in 1.2; Modul aus: Eintrag fehlt bzw. ist grau, keine Fehlermeldung. |  |
| MK44 | Absturzfall des Servers (Fenster „Atlas-Server“) › „Issue anlegen“, mit und ohne Tracker bzw. issues.create. | Mit: Dialog mit Titel und Stapel, danach „An Issue anhängen“ mit den Dateien des Falls; ohne: Ordner des Falls in der Meldungsansicht. |  |

#### Datei- und Prozesszugriffe hinter Adapter

| ID | Handlung | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MK45 | Mit Tracker-Projekt starten, Meldungen abwarten, IDE schließen und neu starten. | `%LOCALAPPDATA%\Atlas\notify.json` wird geschrieben (keine `.atlas-tmp` daneben), nach dem Neustart keine alten Meldungen erneut. |  |
| MK46 | Board und Sprint-Kachel öffnen, dann Netz trennen und Board erneut öffnen. | Letzter Stand aus dem Cache (Datei mit BOM wie bisher), Hinweis „ohne Netz“; „Im Browser öffnen“ öffnet die Seite. |  |
| MK47 | Fenster „Atlas-Issue“: Issue öffnen, Link im Text, verknüpftes fremdes Issue, Knopf „Im Browser“ und Behebung „Im Browser öffnen“. | Jeweils Browser mit der richtigen Seite; `file:`-Links und Adressen mit Benutzer öffnen nichts. |  |
| MK48 | Anhang eines Issues öffnen: einmal PDF/PNG, einmal `.cmd` bzw. Datei ohne Endung. | PDF/PNG im zugehörigen Programm; Ausführbares nur im Explorer markiert, nicht gestartet. |  |
| MK49 | Zeiterfassung: Zeit auf zwei Issues buchen, gleichzeitig in zweiter IDE-Instanz (eigenes Profil). | `time.json` in `%LOCALAPPDATA%\Atlas`, beide Instanzen zählen die Zeit einmal; Sperrdatei `time.json.lock` blockiert nur kurz. |  |
| MK50 | Commit-Präfix: Issue beginnen (Hook anlegen erlauben), committen, Issue beenden; fremder Hook vorhanden. | Eigener Hook angelegt, Präfix in der Nachricht, `atlas-commit-prefix` ohne BOM, nach Beenden entfernt; fremder Hook bleibt unangetastet. |  |
| MK51 | „An Issue anhängen …“ mit Logdatei (auch gesperrt bzw. fehlend), Doppelklick auf eine Zeile, Senden; GitHub-Rückfall. | Log-Ende als Anhang, fehlend nur Hinweis; Doppelklick öffnet die Datei aus `%TEMP%\Atlas\attach`; nach Senden Ordner weg; GitHub öffnet die Seite im Browser. |  |
| MK52 | Modulschalter „Issue-Tracker“ aus, dann Palette/Befehle des Trackers und „Testergebnisse“-Kachel (Build-Seite öffnen); danach IDE schließen. | Ausgeschaltet öffnet und schreibt nichts mehr, keine Fehlermeldung, keine AV beim Schließen; eingeschaltet wieder alles wie oben. |  |

### #1456 Modulgrenzen: Pull in Base, „Gemerkt“ über Vertrag (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| PU1 | Willkommensseite, Schnellaktion „Pull“ (Git) bzw. „Aktualisieren“ (SVN, mit und ohne Externals) mit und ohne lokale Änderungen. | Wie in 1.2: lokale Änderungen sperren, sonst holt bzw. aktualisiert es; Meldung „aktuell“ bzw. neue Commits. |  |
| PU2 | Fenster „Arbeitskopien“: eine Arbeitskopie aktualisieren (mit und ohne Externals), auch bei abgeschalteter Willkommensseite. | Wie in 1.2; das Fenster braucht die Willkommensseite nicht mehr. |  |
| GM1 | Willkommensseite › Weiterarbeiten › Reiter „Gemerkt“ mit Notizen, benannten Lesezeichen (zwei Projekte im selben Ordner, eine Projektgruppe) und Favoriten. | Liste wie in 1.2 (je Projekt Notizen, dann Lesezeichen, Favoriten am Ende); dasselbe Lesezeichen einmal; Filter wie bisher. |  |
| GM2 | Lesezeichen in „Gemerkt“ anklicken, einmal mit benannten Lesezeichen an, einmal aus; Notiz anklicken. | An: Sprung über das Lesezeichen-Modul (findet die verschobene Stelle wieder); aus: Datei und Zeile öffnen; Notiz öffnet Datei und Zeile. |  |
| GM3 | Modulschalter „Lesezeichen“ aus, „Gemerkt“ öffnen und einen Favoriten anklicken; Modul wieder an. | Nur die Favoriten, keine Fehlermeldung; nach dem Einschalten kommen Notizen und Lesezeichen wieder. |  |

### #1456 Pilot: Debugger als eigenes Package (PR #1465)

Kern = `Atlas.IDE.Expert<Suffix>.bpl` (bis zur Umbenennung in `Atlas.IDE.Base`), Debugger = `Atlas.IDE.Debugger<Suffix>.bpl`. Jeder Fall mit Delphi 12 und 13, Win32 und Win64. Bestanden heißt: keine Ausnahme, `TAtlasTeardown.Failures` leer, Diagnosemodus (#479) ohne Einträge, IDE beendet sich ohne Meldung. Ergebnis als Tabelle in #1456, Erkenntnisse zu P2/P7 in ADR 0017 („Drei Mechaniken“) fortschreiben. Eigenes Registry-Profil (`bds -r <Name>`), Known Packages des Standardprofils nicht anfassen.

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| P1 | Frischer Start, Known Packages in der Reihenfolge Kern, Debugger. | Debugger-Beiträge (Exception-Verlauf, Werte im Editor, Visualisierer, Befehle im Atlas-Menü) wie in 1.2. |  |
| P2 | Frischer Start, Reihenfolge Debugger, Kern (Registry-Einträge so anlegen); einmal mit den BPLs im Bpl-Ordner von RAD Studio, einmal nur im Ausgabeordner. | Bpl-Ordner: wie P1. Nur Ausgabeordner: Ladefehler der IDE festhalten (Kern nicht gefunden), kein Absturz. |  |
| P3 | Nur Kern installiert. | Code Insight vollständig, keine Debugger-Beiträge, Modulseite zeigt den Debugger als „nicht installiert“ (falls er sich vorher einmal angemeldet hat). |  |
| P4 | Nur Debugger installiert (Kern liegt im Ordner, steht nicht unter Known Packages). | Hinweis „Atlas-Kern nicht installiert“ bzw. Modul meldet sich still nicht an; kein Absturz. |  |
| P5 | Debugger bei laufender IDE hinzufügen (Komponente › Packages installieren). | Beiträge erscheinen sofort, ohne Neustart. |  |
| P6 | Debugger bei laufender IDE abwählen; danach Hover, Debuggen, Beenden. | Beiträge verschwinden; keine AV. |  |
| P7 | Kern bei installiertem Debugger abwählen. | Meldung der IDE, Reihenfolge der Finalisierungen und Absturz ja/nein festhalten. |  |
| P8 | `cc.ps1`: Kern neu bauen bei geladenem Debugger. | Debugger wird mit entladen, Bau läuft, beide laden wieder. |  |
| P9 | Debugger mit geänderter Vertragsversion (`cAtlasCoreContractVersion` im Debugger +1) gegen den Kern. | Log „Vertragsversion von Base passt nicht, nicht angemeldet“, keine Debugger-Beiträge, kein Absturz. |  |
| P10 | Fenster des Debuggers (Exceptions) angedockt offen, IDE beenden, Debugger deinstallieren, IDE starten. | Desktop lädt ohne Fehlermeldung, Fenster fehlt. |  |
| P11 | `pwsh Tools/Build-Test.ps1` (Win64-Gruppe, Win32-Plugin) und alle Prüfskripte. | 0/0/0, Tests grün; `Build-Test` meldet beide BPLs je Plattform als neu geschrieben. |  |
| P12 | Release-Workflow (`release.yml`) auf einem Test-Tag bzw. lokal nachgestellt. | ZIP enthält je Plattform Kern und Debugger samt Map-Datei unter dem Namen der BPL; beide signiert, falls Signatur an. |  |

### #1456 Alle Module als eigene Packages (PR #1465)

Gilt je Modul-Package (Designer, Rules, Tests, Bookmarks, Analysis, Search, Build, BuildPipeline, Tracker, Welcome). Bestanden wie bei P1–P11.

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| MP1 | Kern und alle Modul-Packages installieren (Kern zuerst), IDE neu starten. | Alle Funktionen wie in 1.2; Modulseite listet jedes Modul als installiert. |  |
| MP2 | Je Modul: bei laufender IDE abwählen, die Funktionen des Moduls aufrufen (Menü, Taste, Palette), wieder hinzufügen. | Abgewählt: Einträge weg, keine AV; hinzugefügt: Einträge sofort zurück. |  |
| MP3 | Nur Kern und Build-Pipeline, ohne Build-Werkzeuge und Tests; dann umgekehrt (Tests ohne Build-Pipeline). | Kein Absturz; Tests ohne Pipeline melden „Build nicht verfügbar“ bzw. fehlen still. |  |
| MP4 | Kern und alle Module in Delphi 12 (290) und 13 (370) nebeneinander im Bpl-Ordner. | Jede IDE lädt nur ihre Suffix-Versionen. |  |

### #1456 Einstellungen der Willkommensseite im Modul (PR #1465)

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| WS1 | Tools › Optionen › Atlas › Willkommensseite öffnen. | Oben der Modulschalter, darunter alle Einstellungen wie in 1.2 (Start, Layout, Bereiche, Schnellaktionen, Atlas entdecken, Hilfe); Unterknoten wie bisher. |  |
| WS2 | Jede Einstellung ändern, OK, Dialog neu öffnen; IDE neu starten. | Alle Werte bleiben; Grenzen wie bisher (z. B. Weiterarbeiten höchstens 20). |  |
| WS3 | Freies Layout: „Neu …“, „Umbenennen …“, „Löschen“, zwischen Layouts wechseln, OK. | Wie in 1.2; je Layout eigene Sichtbarkeit und Spalten, Rückfrage beim Löschen. |  |
| WS4 | „Zählung zurücksetzen“ und „Gesperrte Tipps wieder zeigen“ klicken. | Knöpfe danach gesperrt; Karte „Atlas entdecken“ zeigt gesperrte Tipps wieder, Zählung leer. |  |
| WS5 | „Zur Seite Issue-Tracker“ neben „Meine Issues“; Link „prüfen …“ auf der Seite Versionsverwaltung. | Springt zur Seite Issue-Tracker bzw. zu „Projekte auf Änderungen prüfen“. |  |
| WS6 | Package Atlas.IDE.Welcome abwählen (Komponente › Packages installieren) oder Schalter aus; Optionen öffnen. | Ohne Package nur der Modulschalter, keine AV; Link „prüfen …“ zeigt den Schalter. |  |

### Überholt

CT1–CT4 (Package `Atlas.IDE.Contracts`) entfallen: Das Package gibt es seit dem 04.11.2026 nicht mehr, stattdessen gelten CB1–CB4 in Teil 3.

## Teil 5: Neu seit dem 05.11.2026 (nach Wichtigkeit)

Die Abschnitte stehen in der Reihenfolge, in der sie getestet werden sollten: zuerst Absturz- und Ursachenklärung, dann Prüfregeln und Editor, zuletzt die englischen Texte.

### Module unter „Known Packages“ (Meldung vom 05.11.2026)

Nur im eigenen Profil testen (`bds -r <Name>`, Kopie des Standardprofils mit Base und allen Modulen aus einem Ordner), nie im Standardprofil. Registry-Pfade unten für Delphi 13 und die klassische IDE; die 64-Bit-IDE nutzt `Known Packages x64`.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| KPM1 | IDE im Profil starten, alle Module eingetragen; `atlas.log` öffnen | Zeile `Known Packages: 11 Module im Ordner von Base, fehlend: -; abgeschaltet: -; aus anderem Ordner: -; andere bds.exe: n`; kein Hinweis „Atlas-Module fehlen“ |  |
| KPM2 | IDE schließen, unter `HKCU\Software\Embarcadero\<Profil>\37.0\Known Packages` die Werte für Debugger und Search löschen, IDE starten | Protokoll `fehlend: Debugger, Search`; Benachrichtigung „Atlas-Module fehlen in der IDE“ (Warnung, Plakette gelb) mit „Die Module Debugger, Search …“ und Knopf „Wieder eintragen“ (**Abnahme**) |  |
| KPM3 | Wie KPM2, „Wieder eintragen“ klicken, Registry ansehen, IDE neu starten | Zwei Werte mit Pfad der BPL und Beschreibung „Atlas Debugger“/„Atlas Search“; Hinweis „Atlas-Module wieder eingetragen · Die IDE lädt Debugger, Search beim nächsten Start.“; nach dem Neustart sind beide Module geladen und das Protokoll meldet `fehlend: -` (**Abnahme**) |  |
| KPM4 | Wie KPM3, aber vor dem Neustart die IDE normal beenden und die Registry erneut ansehen | Die Werte stehen noch da. Fehlen sie, schreibt die IDE beim Beenden ihre eigene Liste zurück; bitte melden (das wäre die Ursache vom 05.11.) |  |
| KPM5 | Ein Modul unter *Komponente › Packages installieren* abwählen (Häkchen weg), IDE neu starten | Protokoll `abgeschaltet: <Modul>`, kein Hinweis |  |
| KPM6 | Ein Modul aus einem anderen Ordner eintragen (z. B. `Output\Win32\Release\Bpl`) | Protokoll `aus anderem Ordner: <Modul>`, kein Hinweis |  |
| KPM7 | IDE A läuft; zweite IDE B im selben Profil starten, in B ein Modul über *Komponente › Packages installieren › Entfernen* entfernen | In `atlas.log` von A: `Known Packages geändert: entfernt <Modul>; neu -; in dieser IDE 11 Module angemeldet, andere bds.exe: 1` (A hat die Änderung nicht selbst gemacht) |  |
| KPM8 | In einer IDE Base neu übersetzen, während Base und Module installiert sind (Projektgruppe Atlas, nur `Atlas.IDE.Base` bauen) | Protokoll zeigt, ob und wann Module aus der Liste fallen (`Known Packages geändert: entfernt …; in dieser IDE n Module angemeldet`); Ergebnis bitte melden (zweiter Verdacht für den 05.11.) |  |
| KPM9 | IDE beenden, Protokoll ansehen | Zeile `Known Packages: … (beim Entladen)` mit dem Stand beim Beenden |  |
| KPM10 | Oberfläche auf Englisch, KPM2 wiederholen | „Atlas modules missing from the IDE“, „The modules Debugger, Search are no longer listed under "Known Packages" …“, Knopf „Register again“ |  |
| KPM11 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasKnownPackagesTests` grün |  |

### Einträge in den Hauptthread verfallen mit ihrem Modul (05.11.2026)

Anlass: Zugriffsverletzung 06:31:15 in `Atlas.Core.Diagnostics.MainThread` (Zeile 129, `Proc()` in `Guarded`), aus einem Eintrag eines Moduls, das entladen wurde, während der Eintrag wartete. Geprüft wird mit einem eigenen Registry-Profil (`bds -r <Name>`).

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| HE1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasMainThreadTests` (u. a. `CloseModuleDropsWaitingAndLaterEntries`, `ModuleUnloadedDropsButStaysOpen`, `CloseModuleDropsEntriesOfWorker`, `StopEmptiesPendingList`) und `TModuleRegistryTests.UnregisterDropsQueuedEntriesOfModule` grün, keine Leckmeldung |  |
| HE2 | Win32- und Win64-Plugin bauen | 0/0/0; insbesondere keine Meldung zu `AddModuleUnloadProc(AtlasMainThreadModuleUnload)` und `FindHInstance` in `Atlas.Core.Diagnostics.MainThread` |  |
| HE3 | IDE mit allen Modulen, Projekt öffnen, Willkommensseite und Atlas-Issue offen; in *Komponente › Packages installieren* das Package `Atlas.IDE.Tracker` abwählen (entladen), dann `Atlas.IDE.Welcome` | Kein Absturz, auch nicht in den Sekunden danach; im `atlas.log` gegebenenfalls „Atlas: dropped N queued main thread entries of module $…“ |  |
| HE4 | Wie HE3, während eine Prüfung oder ein Tracker-Abruf läuft (viele Einträge unterwegs) | Kein Absturz; IDE bleibt bedienbar |  |
| HE5 | Nach HE3 die Packages wieder anhaken (laden) | Module melden sich an und arbeiten normal (Willkommensseite aktualisiert sich, Tracker-Vorschau lädt) |  |
| HE6 | IDE mehrmals normal beenden, auch mit laufender Prüfung | Kein Absturz beim Beenden; „Atlas entladen“ im Protokoll ohne Fehler im Schritt MainThread |  |
### Sitzungsmarke der Bau-IDEs: Abgesicherter Start (#722, PR #1808)

Ergänzt den Abschnitt „Abgesicherter Start (#722)“ in `docs/Atlas-Testfaelle.md` (AS1–AS20 sind Teil von 1.x).

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| AS21 | `set ATLAS_NO_SESSION_MARKER=1`, aus dieser Konsole `bds -r <Profil>` starten, warten bis Atlas geladen ist | Unter `%LOCALAPPDATA%\Atlas\Session` entsteht keine `session-<pid>.json` dieser IDE; im Protokoll steht „Atlas gestartet (…), Stufe Normal, Grund None, ohne Sitzungsmarke (ATLAS_NO_SESSION_MARKER)“ |  |
| AS22 | Bei AS21 die IDE im Taskmanager beenden, danach die IDE normal (ohne Variable) starten | Keine Rückfrage „Die letzte Sitzung wurde unerwartet beendet“, Atlas startet normal; `crashCount` in `safemode.json` unverändert |  |
| AS23 | Normale IDE wie AS3 im Taskmanager beenden, danach eine IDE mit `ATLAS_NO_SESSION_MARKER=1` starten und wieder schließen, dann normal starten | Die IDE mit Variable startet normal ohne Rückfrage und lässt die Marke der abgestürzten Sitzung liegen; erst der normale Start fragt wie AS3 |  |
| AS24 | `ATLAS_NO_SESSION_MARKER=1` und `ATLAS_SAFE_MODE=1` setzen, IDE starten | Wie AS12 (nur Einstellungsseite und Statusfeld), aber ohne Startmarke |  |

### Prüffenster: einzelne Projekte der Gruppe (#1843)

Vorbereitung: Plugin mit diesem Stand gebaut, Fenster „Atlas-Prüfung“ (Strg+Alt+P), Projektgruppe mit mindestens drei Projekten, deren Units Befunde haben.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| PEP1 | Projektgruppe mit drei Projekten (z. B. `Atlas.groupproj`) öffnen, Fenster „Atlas-Prüfung“ zeigen, Bereichsliste aufklappen | „Aktuelle Datei“, „Aktuelles Projekt“, „Projektgruppe“, darunter ein Trennstrich (Linie, kein Text) und die drei Projekte in der Reihenfolge des Projektmanagers; das aktive mit „(aktiv)“. Die Klappliste ist breit genug für den längsten Namen; Zeilen nicht abgeschnitten, auch bei 150 % Skalierung (**Abnahme**) | |
| PEP2 | Auf den Trennstrich klicken; mit ↑/↓ über ihn hinweg gehen | Die vorige Wahl bleibt bzw. die Liste springt nicht auf eine leere Wahl; die Befunde ändern sich nicht | |
| PEP3 | Ein nicht aktives Projekt wählen | Nur Befunde aus Units dieses Projekts; Statuszeile „a von b Units geprüft“ zählt dieses Projekt; das aktive Projekt im Projektmanager bleibt unverändert (**Abnahme**) | |
| PEP4 | Nach PEP3 im Projektmanager ein anderes Projekt aktivieren | Das gewählte Projekt bleibt im Fenster; nur die Markierung „(aktiv)“ wandert | |
| PEP5 | Nach PEP3 die IDE schließen und neu starten, Gruppe öffnen, Fenster zeigen | Das Projekt aus PEP3 ist wieder gewählt (`problems.window.scopeProject`) | |
| PEP6 | Nach PEP3 das gewählte Projekt aus der Gruppe entfernen (oder eine andere Gruppe öffnen) | Die Liste zeigt „Aktuelles Projekt“, die Befunde des aktiven Projekts; nach Neustart ebenso | |
| PEP7 | „Projektgruppe“ wählen; eine Unit öffnen, die zu keinem Projekt der Gruppe gehört (z. B. aus der RTL oder einem fremden Ordner), mit Befunden | Ihre Befunde stehen nicht in der Liste (vorher ja); Befunde aller Units der Gruppe stehen da, Units in mehreren Projekten nur einmal | |
| PEP8 | Nur ein einzelnes Projekt ohne Gruppe öffnen bzw. eine Gruppe mit nur einem Projekt | Kein Trennstrich, nur die drei festen Einträge | |
| PEP9 | Optionen › Atlas › Prüfregeln › Prüffenster: „Einzelne Projekte der Gruppe in der Bereichsliste des Fensters“ ausschalten | Liste nur mit den drei festen Einträgen; war ein Einzelprojekt gewählt, gilt „Aktuelles Projekt“. Wieder an: Projekte erscheinen sofort | |
| PEP10 | Oberfläche auf Englisch; danach `Atlas.Tests` bauen und ausführen | „Current file“, „Current project“, „Project group“, Projekte mit „(active)“, Kontrollkästchen „Individual projects of the group in the window's scope list“. Tests: 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasScopeProjectsTests`, `TAtlasProblemsFrameTests.ScopeListOffersGroupProjects`, `TAtlasPluginSettingsTests.ProblemsWindowOptions`, `TAtlasSettingsPageTests.RulesAreaWindowSettings` grün | |

Wer das Dropdown nach einem Andocken oder Themenwechsel mit leeren oder doppelten Einträgen sieht (PEP1), bitte melden.

### Regionen beim Öffnen auf- oder zuklappen (#1814)

Vorbereitung: Plugin mit diesem Stand gebaut. Unit `Regionen.pas` mit drei Regionen auf oberster Ebene (`{$REGION 'Ereignisse'}`, `{$REGION 'Laden'}`, `{$REGION 'Getter'}`), in „Laden“ eine innere Region `{$REGION 'Intern'}`, eine Region innerhalb eines Methodenrumpfs und eine mit `(*$REGION 'Alt'*)`. Datei vor jedem Test schließen.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| RF1 | Optionen › Atlas › Editor: „Regionen beim Öffnen:“ steht auf „unverändert lassen“; `Regionen.pas` öffnen | Faltung wie ohne Atlas (alles offen); im Menü Atlas › Navigation stehen „Alle Regionen zuklappen“ und „Alle Regionen aufklappen“ |  |
| RF2 | Einstellung „alle zuklappen“, `Regionen.pas` öffnen | Nach kurzer Pause sind alle Regionen zugeklappt, auch die innere „Intern“, die im Methodenrumpf und `(*$REGION*)`; andere Blöcke (Klassen, Methoden) bleiben offen; Schreibmarke und Ausschnitt wie vorher (**Abnahme**) |  |
| RF3 | Wie RF2, aber die Datei war vorher mit der Schreibmarke in „Laden“ gespeichert (Desktop merkt sich die Stelle), IDE neu starten | „Laden“ (und eine Region um sie) bleibt offen, die übrigen sind zu; die Marke steht an der gemerkten Stelle |  |
| RF4 | Wie RF2, danach „Laden“ von Hand aufklappen, auf einen anderen Reiter und zurück wechseln | „Laden“ bleibt offen: Atlas klappt nur beim ersten Anzeigen nach dem Öffnen |  |
| RF5 | Mehrere Dateien mit Regionen im Desktop, Einstellung „alle zuklappen“, IDE neu starten, nacheinander alle Reiter anklicken | Jede Datei ist beim ersten Anklicken zugeklappt |  |
| RF6 | Einstellung „alle aufklappen“; Regionen in einer Datei von Hand zuklappen, Datei schließen und wieder öffnen | Alle Regionen offen |  |
| RF7 | Schreibmarke in „Intern“, Menü Atlas › Navigation › „Alle Regionen zuklappen“, danach „Alle Regionen aufklappen“; dasselbe über das Kontextmenü (Atlas › Navigation) und die Befehlspalette | Zu: alle Regionen zu, die Marke steht auf der Kopfzeile von „Laden“. Auf: alle offen. Keine anderen Blöcke verändert (**Abnahme**) |  |
| RF8 | Einstellung „aus (auch keine Befehle)“ | Menü, Kontextmenü und Palette zeigen die Befehle nicht; beim Öffnen ändert Atlas nichts |  |
| RF9 | Oberfläche auf Englisch | „Regions when a file opens:“ mit „leave unchanged“, „collapse all“, „expand all“, „off (no commands either)“; Befehle „Collapse all regions“, „Expand all regions“ |  |
| RF10 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasRegionFoldsTests`, `TAtlasRegionFoldsTextsTests`, `TAtlasEditingSettingsTests.RegionFoldsOptions` grün |  |

Trifft „nächsten Block zuklappen“ an der Kopfzeile einer Region einen anderen Block als die Region (RF2), bitte melden: Dann braucht Atlas einen anderen Weg.

### Fehlalarme von vier Prüfregeln (method-without-self, handle-leak, field-not-freed, unused-suppression)

Vorbereitung: Plugin und Server mit diesem Stand gebaut; Testprojekt mit eigener `atlas.json`, darin `"rules": {"method-without-self": "hint"}`. Fenster „Atlas-Prüfung“ offen.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| FPR1 | Unit mit `TMelder = class(TNotifierObject, IOTAWizard)` und `function GetIDString: string;` (Rumpf `Result := 'X.Melder';`), uses `ToolsAPI` | Kein `method-without-self` an `GetIDString`, auch ohne ToolsAPI-Quelltext im Index |  |
| FPR2 | `TVergleich = class(TInterfacedObject, IComparer<Integer>)` mit `function Compare(const A, B: Integer): Integer;` (Rumpf `Result := A - B;`) | Kein `method-without-self` an `Compare` |  |
| FPR3 | `IBasis = interface procedure Zeige; end; IKind = interface(IBasis) end; TZeiger = class(TInterfacedObject, IKind)` mit `Zeige` ohne Self und einer weiteren Methode `Doppelt(A: Integer): Integer` ohne Self | Nur `TZeiger.Doppelt` wird gemeldet, `Zeige` nicht |  |
| FPR4 | Funktion `function Darf: Boolean; var Token: THandle; begin Result := OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token); if not Result then begin Exit; end; CloseHandle(Token); end;` | Kein `handle-leak` |  |
| FPR5 | Wie FPR4, aber `CloseHandle(Token)` nur im Zweig `if not Result then` | `handle-leak` „Token nicht auf jedem Weg mit CloseHandle geschlossen“ bleibt |  |
| FPR6 | Klasse mit Feld `FPos: TPos;`, wobei `TPos = Atlas.Text.Lines.TTextPosition` (Alias anderen Namens in einer anderen Unit des Projekts), im Konstruktor `FPos := TPos.Create(1, 2);` | Kein `field-not-freed` an `FPos` |  |
| FPR7 | In einer Unit ohne `Winapi.Windows` im uses `RenameFile(A, B); // lsp-ignore: inline-not-expanded`, Datei speichern | Kein Hinweis `unused-suppression`, der Kommentar bleibt beim Speichern stehen; bitte zusätzlich melden, ob ohne den Kommentar `inline-not-expanded` (H2443, Winapi.Windows fehlt) erscheint |  |
| FPR8 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TMethodLookupTests`, `TMethodWithoutSelfRuleTests.InterfaceMethodsAreSilent`, `TFlowHandleLeakTests`, `TFreeFieldTypesTests.FollowsAliasesOfOtherUnits`, `TRuleEngineTests.UndecidedLineKeepsSuppression`, `TInliningRulesTests.UnknownCallKeepsSuppression` grün |  |

### Fehlalarme der Stilregeln aus Marcos Lauf (06.11.2026)

Vorbereitung: Plugin und Server mit diesem Stand gebaut. In der `atlas.json` von Atlas `"minConfidence": "low"` und die Regeln `naming-prefix`, `magic-number`, `hardcoded-string`, `public-field`, `method-without-self`, `string-concat-in-loop`, `loop-invariant-call`, `missing-begin-update` auf `"info"`; dann im Fenster „Atlas-Prüfung“ die Projektgruppe Atlas prüfen.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| RFP1 | Befunde mit der Liste vom 06.11. vergleichen (`hardcoded-string`) | Keine Meldung mehr für `TAtlasGuard.Log(…)`, `Diagnose(…)`, `Assert(…)`, `FormatDateTime`-Masken, `'<tr …>'`, `'## …'`, `Font.Name := 'Segoe UI'`; Texte wie `'nur https'` bleiben (**Abnahme**) |  |
| RFP2 | `magic-number` bei `EnsureRange(…, 0, $FFFF)`, `MulDiv(…, 96)`, Vektor-Icons `[P(3.5, 1.5), …]` | Still; `SetBounds(12, 9, 360, 23)` im Tastenkürzel-Fenster bleibt gemeldet |  |
| RFP3 | `naming-prefix` in Vergleichern `function(const A, B: …)` und in Handlern, die der Code zuweist (`FEvents.OnEditorPaintLine := PaintLine`) | Still für `A`, `B` und die Parameter der Handler |  |
| RFP4 | `public-field` in `Atlas.Core.Problems.Store` (`protected type TEntry`) | Still; Felder öffentlicher Klassen bleiben gemeldet |  |
| RFP5 | `method-without-self`: `TAtlasKeyMapForm.FormClose`, `TStopTicker.Tick` (`OnTimer := TStopTicker(FTicker).Tick`) | Still |  |
| RFP6 | `uses-unit-not-found` in `Atlas.Common.dpk` (`requires Atlas.Text`) ohne gebaute `Atlas.Text.dcp` | Still, weil Atlas.Text in derselben Projektgruppe steht |  |
| RFP7 | Atlas.Windows.Console.StdStreams öffnen | Kein „NoErrMsg ist nicht deklariert“ (Index neu aufgebaut, Version 32) |  |
| RFP8 | Atlas.Common.Lsp.PullDiagnostics Zeile mit `raise FErrorClass.Create` | Weder `class-reference-nonvirtual-constructor` noch `unused-suppression` |  |
| RFP9 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; neue Tests in Style, Performance, Naming, General, MemberHides, ClassReferences, ControlFlow, EventAssignments, UnitLookup grün |  |

### Typen aus den Packages der IDE (atlas/ideTypes, PR #1816)

Vorbereitung: ein Fremd-Package mit eigenen Komponententypen ist in der IDE installiert (Typ hier `TFremdTyp` in Unit `FremdUnit`).

| Nr. | Schritte | Erwartet | Ergebnis |
|----|----------|-----------|---|
| IT1 | IDE starten, Atlas-Protokoll öffnen | Zeile `IDE-Typen: N, X ms, RTTI unlesbar: 0` mit N > 0 und kleiner Dauer |  |
| IT2 | Komponententyp aus einer Unit verwenden, die im uses steht, deren .pas im Suchpfad aber eine ältere Fassung ohne diesen Typ ist | Keine Meldung „Typ … ist nicht deklariert“ (**Abnahme**) |  |
| IT3 | Derselbe Typ ohne uses-Eintrag | Meldung erscheint; die Schnellkorrektur bietet „uses <Unit> ergänzen“ mit der Unit aus der IDE an (**Abnahme**) |  |
| IT4 | `TFremdTyp.Create(nil)` im Code | Keine Meldung von `unresolved-identifier` |  |
| IT5 | Vervollständigung von `TFre…`, Eintrag übernehmen | Typ mit „<Unit> (uses ergänzen)“; nach dem Übernehmen steht die Unit im uses |  |
| IT6 | Wie IT5, die Unit steht schon im uses | Unitname als Detail, kein zusätzlicher uses-Eintrag |  |
| IT7 | Vervollständigung von RTL- und VCL-Typen (z. B. `TButton`) | Kein Typ doppelt |  |
| IT8 | IDE ohne Fremd-Packages starten | Start unverändert, Protokollzeile zeigt eine kleine Zahl |  |

### Mitglieder der IDE-Typen für Hover und Vervollständigung (atlas/ideMembers)

Vorbereitung wie bei IT: Fremd-Package installiert, Unit `FremdUnit` ohne .pas im Suchpfad, darin `TFremdTyp` mit Properties, Methoden und einem Aufzählungstyp.

| Nr. | Schritte | Erwartet | Ergebnis |
|----|----------|-----------|---|
| IM1 | Projekt öffnen, warten bis der Index fertig ist, Atlas-Protokoll öffnen | Zeile `IDE-Mitglieder: N Units, M Typen, X ms, RTTI unlesbar: 0` mit N > 0; Dauer klein |  |
| IM2 | Maus über `TFremdTyp` im Code | Hover zeigt die Klasse mit Unit `FremdUnit` (**Abnahme**) |  |
| IM3 | `var G: TFremdTyp;` … Maus über `G.EineProperty` | Hover zeigt `property EineProperty: TTyp;` (**Abnahme**) |  |
| IM4 | `G.` tippen | Vervollständigung listet Properties und Methoden von `TFremdTyp` samt geerbten aus dem Vorfahren (**Abnahme**) |  |
| IM5 | `G.EineMethode(` tippen | Parameterhilfe zeigt die Parameter mit Typen |  |
| IM6 | Methode mit Parameter vom Aufzählungstyp aufrufen, im Parameter Strg+Leertaste | Die Werte des Aufzählungstyps werden angeboten |  |
| IM7 | Im Hover Strg+Klick bzw. auf den Typverweis klicken | Kein Fehlerdialog „Datei nicht gefunden“, nichts passiert |  |
| IM8 | Strg+Klick im Editor auf `EineProperty` | Wie bisher (kein Sprung in eine Ersatz-Unit) |  |
| IM9 | Prüffenster nach IM1–IM6 | Keine neuen Befunde in fremden Units, keine Datei `atlas-ide:` |  |

### Unit-Aliase im uses (WinTypes, WinProcs)

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| UAL1 | VCL-Projekt ohne eigene Unit-Aliase, in einer Unit `uses WinTypes, WinProcs;` schreiben, speichern | Kein Befund `uses-unit-not-found` („Unit WinTypes nicht gefunden (wie F2613)“) mehr; dcc übersetzt ohne Meldung |  |
| UAL2 | In derselben Unit `var R: TRect;` und `MessageBeep(0);` verwenden, Strg+Klick auf `MessageBeep` | Keine Befunde zu unbekannten Bezeichnern; Strg+Klick öffnet `Winapi.Windows.pas`; Hover zeigt die Deklaration |  |
| UAL3 | Strg+Klick auf `WinTypes` im uses | `Winapi.Windows.pas` öffnet sich |  |
| UAL4 | Unit mit `uses WinTypes;`, aus der nichts verwendet wird | `unused-uses` blendet `WinTypes` ab; mit `TRect` im Code bleibt es normal |  |
| UAL5 | In den Projektoptionen unter „Unit-Aliase“ `Alt=System.SysUtils` eintragen, speichern, Projekt neu laden, `uses Alt;` und `IntToStr(1)` schreiben | Kein `uses-unit-not-found`, `IntToStr` löst sich auf; ohne den Eintrag meldet Atlas wie dcc F2613 |  |
| UAL6 | `uses DbiTypes;` in einem Projekt ohne BDE | Atlas meldet `uses-unit-not-found` wie dcc (Ziel-Unit BDE fehlt) |  |

### Published-Mitglieder im Hover scrollen (#1841)

Vorbereitung: Plugin mit diesem Stand gebaut, `hover.membersMaxLines` unverändert (15). Eine Unit mit `uses Vcl.Forms, Vcl.StdCtrls;` und `var F: TForm; B: TButton;`.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| HMS1 | Maus über `TForm`, im Hover bei PROPERTIES „+ n weitere Properties“ klicken | Der Hinweis bleibt im Bildschirm; die Tabelle zeigt 15 Zeilen, rechts ein schmaler Daumen; Zusammenfassung, Schalter und Aktionsleiste stehen fest (**Abnahme**) |  |
| HMS2 | Wie HMS1, Mausrad über der Tabelle nach unten bis zum Ende | Je Stufe drei Zeilen; am Ende stehen EREIGNISSE und ihre letzte Zeile, der Daumen unten; nichts ragt über die Linie darüber oder in die Aktionsleiste (**Abnahme**) |  |
| HMS3 | Bei HMS2 „+ n weitere Ereignisse“ bzw. den Titel EREIGNISSE ▾ anklicken, wenn sichtbar | Klick wirkt; der Bereich bleibt an seiner Stelle bzw. springt höchstens an das neue Ende |  |
| HMS4 | Mausrad über der XMLDoc eines Typs mit langer Doku und vielen Mitgliedern | Die Doku scrollt, die Mitglieder nicht; über den Mitgliedern scrollen nur diese |  |
| HMS5 | Hover nahe am unteren Bildschirmrand, Mitglieder aufklappen | Der Hinweis wächst nach oben und bleibt ganz sichtbar; der Rollbereich ist höchstens so hoch wie der Platz |  |
| HMS6 | Optionen › Atlas › Editor: „Mitglieder im Hover: höchstens Zeilen ohne Scrollen“ auf 5, dann auf 0 | 5: Tabelle fünf Zeilen hoch. 0: so hoch wie der Bildschirm zulässt, darunter kein Daumen |  |
| HMS7 | IDE auf Englisch | Text der Option „Members in the hover: max. lines before scrolling (0 = screen)“ |  |
| HMS8 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `THoverLayoutTests.PublishedMembersScroll`, `ScrolledMembersDropHiddenHits`, `TAtlasPluginSettingsTests.HoverMembersMaxLinesRoundTrip` grün |  |

### Sprache der Serverbefunde ohne `language` (#1458, #446)

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| SPB1 | `"language"` aus `%APPDATA%\Atlas\settings.json` entfernen, IDE auf Deutsch starten | In `atlas.log` die Zeile „Sprache der Oberfläche: de (…)“ mit Quelle (Ressourcen, Registry Locales, Windows oder Vorgabe) und „initialize mit locale de“; Befunde im Editor und im Fenster „Atlas-Prüfung“ deutsch (**Abnahme**) |  |
| SPB2 | Wie SPB1, IDE mit BDSSetLang auf Englisch umstellen, neu starten | Zeile „Sprache der Oberfläche: en (…)“, „initialize mit locale en“; Atlas-Menü und Befunde englisch |  |
| SPB3 | Wie SPB1, falls die Zeile „en“ zeigt, obwohl die IDE deutsch ist: Zeile und den Wert unter `HKCU\Software\Embarcadero\Locales` für bds.exe melden | Ursache der Fehlerkennung nachvollziehbar |  |
| SPB4 | Tools › Optionen › Atlas › Server: „Index-Cache löschen“ in deutscher IDE ohne `language` | Antwort des Werkzeugs deutsch (Aufruf mit `--locale de`) |  |
| SPB5 | `"language": "en"` in settings.json, deutsche IDE | Befunde englisch, Oberfläche des Plugins bleibt deutsch |  |
| SPB6 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasIdeLanguageTests` und `TAtlasTextLanguageTests` grün |  |

### Kontextmenü Atlas im Editor: Untermenüs und Tastenkürzel (05.11.2026)

Ausgangslage: Das Untermenü *Atlas* im Kontextmenü des Editors war mit rund 40 Einträgen höher als der Bildschirm (oben abgeschnitten), und die Tastenkürzel klebten direkt am Text („FormatierenStrg+Alt+Umsch+L“).

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| EK1 | Rechtsklick im Editor › *Atlas* | Oben „Code-Aktionen“ und „Erzeugen …“, Trennlinie, Untermenüs *Navigation*, *Bearbeiten*, *Suchen und analysieren*, *Befunde*, Trennlinie, *Debuggen*, *Tests*, *Notizen und Lesezeichen*, „Weg von hier nach …“, „Issue anlegen …“, Trennlinie, „Element ausblenden …“; das Menü passt auf den Bildschirm (**Abnahme**) |  |
| EK2 | Untermenüs öffnen | Kürzel stehen in einer eigenen Spalte rechtsbündig (z. B. *Bearbeiten › Formatieren* Strg+Alt+Umsch+L, *Befunde › Nächster Befund* Strg+Alt+F8), nicht mehr am Text (**Abnahme**) |  |
| EK3 | Jeden Eintrag einmal per Maus wählen (Navigation, Bearbeiten, Suchen und analysieren, Befunde, Debuggen, Tests, Notizen und Lesezeichen) | Jeder Befehl läuft genau einmal |  |
| EK4 | Kontextmenü einmal öffnen und schließen, danach im Editor Strg+Alt+Umsch+L, Strg+Alt+K, Alt+Enter, Strg+W drücken | Jeder Befehl läuft genau einmal (kein doppeltes Formatieren, kein zweiter Dialog) (**Abnahme**) |  |
| EK5 | Nach EK4: Strg+Umschalt+↑ in einer Methode, dann außerhalb einer Methode; Strg+. auf einer Zeile ohne Element | In der Methode Wechsel Deklaration ⇄ Implementierung; außerhalb die Klassennavigation der IDE bzw. IDE Insight wie ohne Atlas |  |
| EK6 | *Tools › Optionen › Atlas › Befehle*: Kürzel für „Formatieren“ ändern, OK, Kontextmenü öffnen | Das neue Kürzel steht im Menü, ohne Neustart |  |
| EK7 | Prüfregeln aus (`problems.enabled`), Kontextmenü | *Befunde* zeigt nur „Nächster Befund“ und „Vorheriger Befund“, „Datei jetzt prüfen“ fehlt |  |
| EK8 | Module Debugger und Tests über die Modulschalter abschalten, Kontextmenü | Untermenüs *Debuggen* und *Tests* fehlen, keine leeren Untermenüs, keine doppelte Trennlinie; wieder einschalten: sie erscheinen ohne Neustart |  |
| EK9 | Englische Oberfläche | Untermenüs *Navigation*, *Edit*, *Search and analyze*, *Findings*, *Debugging*, *Tests*, *Notes and bookmarks*; Kürzel rechtsbündig |  |
| EK10 | Rechtsklick in die Rinne einer anderen Zeile › *Atlas › Notizen und Lesezeichen › Notiz an dieser Zeile…* | Dialog nennt die angeklickte Zeile (wie NO6) |  |
| EK11 | `Atlas.Tests` bauen und ausführen, Plugin-Packages bauen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasMenuSlotsTests`, `TAtlasKeyStrokeTests` grün |  |

### Formatieren mit Markierung (PR #1796)

Ursache noch offen: Der Knopf „Formatieren“ in der Editorleiste formatiert womöglich die ganze Unit trotz Markierung. #1796 protokolliert Markierung und Antwort anonym; die Zeilen bitte melden.

| Nr. | Schritte | Erwartet | Ergebnis |
|----|----------|-----------|---|
| FMK1 | Ein paar Zeilen markieren, Knopf „Formatieren“ in der Editorleiste drücken | Nur die Markierung wird formatiert; sonst melden |  |
| FMK2 | Dieselbe Markierung mit Strg+Umschalt+Alt+L formatieren | Nur die Markierung wird formatiert |  |
| FMK3 | Im Atlas-Protokoll die `Format:`-Zeilen von FMK1 und FMK2 vergleichen | Beide nennen denselben Bereich; Unterschied bitte mit den Zeilen melden |  |

### Datei prüfen über die Atlas-Statusleiste statt über einen Knopf (05.11.2026)

In `docs/Atlas-Testfaelle.md` und PR #1803 heißen die Tests PS1–PS7; hier PSL1–PSL7, damit sie nicht mit PS1–PS4 (Projekt-Zusammenfassungen) in Teil 4 verwechselt werden.

Vorbereitung: Win32-Plugin gebaut, eigenes Registry-Profil; Prüfregeln (`problems.enabled`) und Atlas-Statusleiste an, Fenster „Atlas-Prüfung“ offen, eine Unit mit Befunden im Editor.

| Nr. | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| PSL1 | `problems.update` nacheinander auf „Live“, „Beim Speichern“ und „Nur auf Anforderung“ | Rechts im Fenster „Atlas-Prüfung“ steht nur die Anzeige „● Live“, „Beim Speichern“ bzw. „Manuell“; ein Knopf „Datei jetzt prüfen“ erscheint in keinem Modus, nichts ist abgeschnitten (**Abnahme**) |  |
| PSL2 | „Beim Speichern“; in der Unit einen Befund einbauen, nicht speichern, Maus über „beim Speichern · Projekt xx %“ in der Atlas-Statusleiste | Tooltip endet mit „Klick: Datei jetzt prüfen“ |  |
| PSL3 | In PSL2 auf „beim Speichern · Projekt xx %“ klicken | Die offene Datei wird sofort geprüft, auch ungespeichert; der neue Befund erscheint in Statusleiste und Fenster, die übrigen Units werden nicht neu geprüft (**Abnahme**) |  |
| PSL4 | „Nur auf Anforderung“; Befund einbauen, auf „manuell · …“ in der Statusleiste klicken | Die offene Datei wird geprüft wie in PSL3 |  |
| PSL5 | „Live“; auf die Live-Prüfung in der Statusleiste klicken | Wie bisher: „Atlas prüft alle Units neu …“, alle Units werden neu geprüft |  |
| PSL6 | Befehlspalette › „Datei jetzt prüfen“ und Strg+Umschalt+Alt+P | Beides prüft die offene Datei weiterhin |  |
| PSL7 | IDE auf Englisch (Atlas-Sprache English), PSL1–PSL3 wiederholen | Fenster „Atlas Findings“ ohne Knopf „Check file now“; Tooltip der Statusleiste endet mit „Click: check this file now“, Klick auf „on save · project xx %“ prüft die Datei |  |
### Zusatzfelder in der Atlas-Statusleiste (05.11.2026)

Vorbereitung: Win32-Plugin gebaut, eigenes Registry-Profil; Atlas-Statusleiste an (`editor.statusBar`) mit dem Element „Status“; Modul Analyse installiert, `architecture.enabled` und `build.showInterfaceCost` an; Unit `Unten.pas` aus IK1 offen.

| Nr. | Schritt | Erwartung | Ergebnis |
|---|---|---|---|
| ZF1 | Einfügemarke in den interface-Teil von `Unten.pas` | „interface-Änderung: 2 Units werden neu kompiliert“ steht in der Atlas-Statusleiste direkt hinter dem Status (und hinter einer Plakette ungelesener Benachrichtigungen), mit Trennstrich; in der Statuszeile der IDE steht das Feld nicht mehr (**Abnahme**) |  |
| ZF2 | Maus über das Feld aus ZF1 | Tooltip nennt die ersten Units wie bisher; das Feld wird hervorgehoben |  |
| ZF3 | Klick auf das Feld aus ZF1 | „Unit-Beziehungen“ öffnet sich mit „Abhängigkeiten dieser Unit“ (wie IK-Klick in der Statuszeile) |  |
| ZF4 | Einfügemarke in den implementation-Teil | Das Feld verschwindet aus der Atlas-Statusleiste, ohne Lücke oder doppelten Trennstrich |  |
| ZF5 | Zahnrad › „Status“ ausblenden, dann interface-Teil wie ZF1 | Das Feld steht wieder in der Statuszeile der IDE (zusammen mit dem Atlas-Feld); nach dem Einblenden von „Status“ wieder in der Atlas-Leiste |  |
| ZF6 | Zahnrad › „Statusleiste ausblenden“ | Atlas-Feld und alle Zusatzfelder stehen in der Statuszeile der IDE; Klick auf das Feld aus ZF1 dort öffnet „Unit-Beziehungen“ |  |
| ZF7 | Mit Leiste und Status: Startprofil (#575), Compilerschalter, Schnell-Lesezeichen, Mehrfachcursor oder Zeit eines Tracker-Issues auslösen | Auch diese Felder stehen hinter dem Status in der Atlas-Leiste statt in der Statuszeile; ein Klick tut dort dasselbe wie vorher in der Statuszeile |  |
| ZF8 | Editorfenster schmal ziehen | Zusatzfelder kürzen sich mit „…“ zusammen mit der Live-Prüfung, nach der Methode; Zähler bleiben; nichts bricht um |  |
| ZF9 | Zweites Editorfenster öffnen (Ansicht › Neues Editorfenster), dort interface-Teil wie ZF1 | Die Leiste jedes Fensters zeigt die Zusatzfelder hinter ihrem Status |  |
### Klassenvervollständigung: Typkommentar, Reihenfolge, Vorbefüllung (#1834, #1835, #1836, #1837, #1838)

Vorbereitung: Plugin und AtlasServer mit diesem Stand gebaut, Einstellungen unverändert (`classCompletion.typeComment` = `brace`, `lifecycleFirst` und `bodyStubs` an, `editor.methodPlacement` = `grouped`). Neue Unit `Fenster.pas`:

```pascal
unit Fenster;

interface

uses
  System.Classes;

type
  /// <summary>Hauptfenster der Anwendung.</summary>
  TFenster = class(TComponent)
  private
    FName: string;
    procedure Zeichnen;
    function GetName: string;
    procedure SetName(const AValue: string);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Name: string read GetName write SetName;
  end;

implementation

end.
```

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| KK1 | Schreibmarke auf `TFenster = class`, Glühbirne › „6 fehlende Methodenrümpfe für TFenster erzeugen“ | Über den Rümpfen steht `{ TFenster }` mit einer Leerzeile danach (**Abnahme**) |  |
| KK2 | Rückgängig, IDE-Klassenvervollständigung Strg+Umschalt+C | Die IDE legt `{ TFenster }` an; Atlas legt keinen zweiten Kommentar an |  |
| KK3 | `classCompletion.typeComment` auf `line`, KK1 wiederholen | Drei Zeilen `//----…` / `// TFenster` / `//----…`, Breite nach `format.maxLineLength` bzw. 80 |  |
| KK4 | `typeComment` auf `summary`, KK1 wiederholen | `{ TFenster: Hauptfenster der Anwendung. }`; ohne `<summary>` über der Klasse wie `brace` |  |
| KK5 | `typeComment` auf `region`, KK1 wiederholen | `{$REGION 'TFenster'}` vor dem ersten und `{$ENDREGION}` hinter dem letzten Rumpf; die Region lässt sich falten |  |
| KK6 | `typeComment` auf `off`, KK1 wiederholen | Kein Kommentar, Rümpfe wie bisher (**Abnahme**) |  |
| KK7 | Zweite Klasse `TLeiste` unter `TFenster` deklarieren, ihre Rümpfe mit Kommentar oben in die implementation verschieben, „implementation wie Klasse ordnen“ | `{ TLeiste }` wandert mit den Rümpfen von TLeiste hinter TFenster; Vorschau zeigt die Bewegungen |  |
| KK8 | Wie KK7 mit `region` | Region samt Inhalt wandert mit; Rümpfe in der Region bleiben nicht mehr stehen |  |
| KK9 | Einstellungsseite Eingabehilfen, Abschnitt `classCompletion` auf Deutsch und Englisch | Auswahl brace/line/summary/region/off und zwei Schalter mit Beschreibung; englisch „Class completion …“ |  |
| MRG1 | KK1 | Reihenfolge Create, Destroy, GetName, SetName, Loaded, Zeichnen (**Abnahme**) |  |
| MRG2 | Rümpfe von Hand in Deklarationsreihenfolge bringen, „implementation wie Klasse ordnen“ | Vorschau verschiebt Create und Destroy nach oben, GetName/SetName dahinter; Ordnen ein Rückgängig-Schritt |  |
| MRG3 | Optionen › Atlas › Editor: „Methodenrümpfe ordnen“ zeigt „gruppiert, Konstruktor zuerst“ als Vorgabe; auf „wie die Deklaration“ stellen, MRG2 | Create und Destroy stehen trotzdem oben (`lifecycleFirst`), danach Zeichnen, GetName, SetName, Loaded |  |
| MRG4 | `classCompletion.lifecycleFirst` aus, MRG3 | Streng wie deklariert: Zeichnen, GetName, SetName, Loaded, Create, Destroy |  |
| MRG5 | Neue Methode `procedure Laden;` unter `public` ergänzen, Strg+Umschalt+C | Rumpf landet hinter Zeichnen (Gruppe „übrige“), nicht vor Create |  |
| MRG6 | Englische IDE: Optionsseite | „grouped, constructors first“ in der Auswahl |  |
| RV1 | KK1, Rümpfe ansehen | `Create`: `inherited Create(AOwner);`, `Destroy`: Leerzeile, dann `inherited;`, `GetName`: `Result := FName;`, `SetName`: `FName := AValue;`, `Loaded`: `inherited Loaded;`, `Zeichnen` leer (**Abnahme**) |  |
| RV2 | Feld `FName` in `FText` umbenennen, Rümpfe löschen, KK1 | Getter und Setter leer (kein Feld F<Name>) |  |
| RV3 | `function Wert(A, B: Integer): Integer; override;` ergänzen, Rumpf erzeugen | `Result := inherited Wert(A, B);` |  |
| RV4 | Klasse ohne Vorfahren (`class`), `constructor Create;` | Rumpf leer (kein `inherited` bei TObject) |  |
| RV5 | `classCompletion.bodyStubs` aus, KK1 | Alle Rümpfe leer wie bisher |  |
| RV6 | Unit übersetzen nach RV1 | Übersetzt ohne Fehler und Warnungen |  |
| KU1 | Nach KK1 `TFenster` umbenennen (Umbenennen-Dialog) in `TMainWindow` | Vorschau nennt die Zeile `{ TFenster }  →  { TMainWindow }`; danach steht `{ TMainWindow }` über den Rümpfen (**Abnahme**) |  |
| KU2 | Kommentar `// TFenster ist hier gemeint` über einer freien Routine, KU1 | Dieser Kommentar bleibt unverändert |  |
| KU3 | „Klasse in eigene Unit verschieben“ auf `TFenster` | Neue Unit enthält `{ TFenster }` vor den Rümpfen; in der alten Unit bleibt kein `{ TFenster }` zurück |  |
| KU4 | `classCompletion.typeComment` auf `off`, KU1 und KU3 | Kommentar bleibt wie bisher stehen (Umbenennen ändert ihn nicht, Verschieben lässt ihn zurück) |  |
| KK10 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TTypeCommentsTests`, `TClassBodiesTests`, `TClassCompletionTests`, `TMethodOrderTests`, `TMoveClassTests.MovesTypeComment`, `TLspRenameTests.RenamesTypeComments`, `TConfigurationParserTests.ReadsClassCompletion`, `TAtlasEditingSettingsTests.MethodPlacementOptions` grün |  |

### Benachrichtigungs-Plakette immer sichtbar (#1155, PR #1802)

Ergänzt den Abschnitt „Atlas-Statusleiste (#1155)“ in `docs/Atlas-Testfaelle.md`.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| ASL19 | Benachrichtigungen an, keine ungelesenen (z. B. nach „Alle gelesen“), hell und dunkel | Hinter dem Status steht eine neutrale Plakette „0“; Tooltip „0 ungelesene Benachrichtigungen; …“ (englisch „0 unread notifications; …“); Klick öffnet die Liste |  |
| ASL20 | Build mit Fehlern, dann in der Liste „Alle gelesen“ | Plakette wird rot mit „1“, danach wieder neutral „0“; sie verschwindet nicht |  |
| ASL21 | `notifications.enabled` aus (Seite *Allgemein* oder Schnellschalter), danach wieder an | Aus: keine Plakette in der Leiste; an: Plakette „0“ ohne Neustart wieder da |  |
| ASL22 | Element „Status“ in „Leiste anpassen“ abwählen | Keine Plakette in der Leiste; im Atlas-Feld der IDE-Statuszeile erscheint sie wie bisher nur mit ungelesenen Einträgen |  |

### Kräftige Farben im Benachrichtigungsfenster

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| BN1 | Dunkles Design, Benachrichtigungen mit Warnung und Fehler (z. B. Build mit Warnungen), Glocke in der Atlas-Statusleiste anklicken | Gelbes „!“ und rotes „×“ so kräftig wie die rote/gelbe Plakette unten in der Statusleiste; Zeichen dunkel und gut lesbar (**Abnahme**) |  |
| BN2 | Wie BN1, ungelesene Einträge | Balken links in derselben kräftigen Farbe wie die Plakette |  |
| BN3 | Helles Design, wie BN1 | Kräftige Füllung mit dunklem Rand; „!“ auf Gelb dunkel, „×“ auf Rot weiß; Info-Einträge blau |  |
| BN4 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasNotificationsWindowTests` grün |  |

### Marke „braucht kein Self“ (#686, PR #1806)

MOS13 und MOS14 sind neu, MOS1 und MOS2 angepasst (Abschnitt „Methode ohne Self (#686)“ in `docs/Atlas-Testfaelle.md`).

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| MOS1 | In einer Klasse `function TRechner.Doppelt(A: Integer): Integer; begin Result := A * 2; end;` (ohne Felder), Datei öffnen | Hinter dem Kopf der Implementierung die graue Marke „braucht kein Self“ (englische IDE: „Self unused“); nicht hinter Methoden, die Felder, Properties, Self oder inherited nutzen |  |
| MOS2 | Rechtsklick auf die Marke, „Ausblenden“ hier; danach Einstellung „Marke ‚braucht kein Self‘“ auf der Seite Editor aus | Marke verschwindet an dieser Zeile bzw. überall; nach Wiedereinschalten wieder da |  |
| MOS13 | Cursor irgendwo anders, Linksklick auf die Marke „braucht kein Self“ hinter `Doppelt` | Cursor steht am Ende des Kopfs, die Auswahl der Code-Aktionen öffnet sich wie mit Strg+. (Umwandlungen wie MOS3); Klick mit Strg/Umschalt/Alt tut nichts Besonderes |  |
| MOS14 | Marke sichtbar, dann Einstellung „Marke ‚braucht kein Self‘“ aus, ohne zu scrollen an dieselbe Stelle klicken | Nur der normale Klick des Editors, keine Aktionsauswahl; Klick auf eine Blockende-Beschriftung springt weiter zum Blockanfang |  |

### Lokale Routinen in Paarfarben und Blocklinien (#1788)

Vorbereitung: Win32-Plugin gebaut, eigenes Registry-Profil; Paarfarben und Blocklinien an. Unit mit dieser Routine öffnen:

```pascal
procedure TForm1.Laden;
var
  mListe: TStringList;

  function Gueltig(const AName: string): Boolean;
  begin
    Result := AName <> '';
  end;

begin
  mListe := TStringList.Create;
  try
    if Gueltig('x') then
    begin
      mListe.Add('x');
    end;
  finally
    mListe.Free;
  end;
end;
```

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| LR1 | Vorgabe (`highlight.nestedRoutines` = `deeper`) | `procedure`, äußeres `begin`/`end` und ihre Linie in der ersten Paarfarbe (blau); `function Gueltig`, ihr `begin`/`end` und ihre Linie in der zweiten (rot) (**Abnahme**) |  |
| LR2 | *Tools › Optionen › Atlas › Editor*: „Lokale Routinen färben“ zeigt drei Einträge ohne Buchstaben: „wie die äußere Routine“, „eine Stufe tiefer“, „in eigener Farbe, Blocklinie gestrichelt“ | Wie beschrieben; „eine Stufe tiefer“ gewählt |  |
| LR3 | „wie die äußere Routine“, OK | Gueltig wieder in derselben Farbe wie die äußere Routine (Stand vor #1788), ohne Neustart |  |
| LR4 | „in eigener Farbe, Blocklinie gestrichelt“, OK | `function`, `begin`, `end` von Gueltig in Bernstein, ihre Blocklinie gestrichelt; `try`/`if` der äußeren Routine unverändert |  |
| LR5 | Reiter *Farben*: Flächen „Lokale Routinen im hellen/dunklen Thema“ anklicken, Farbe wählen, OK | Neue Farbe sofort im Editor; „Standardfarben“ setzt sie zurück, gespeichert bleibt dann leer |  |
| LR6 | „Zeilen lokaler Routinen hinterlegen“ an, OK | Zeilen von `function Gueltig` bis zu ihrem `end;` schwach in ihrer Farbe hinterlegt, Text gut lesbar; die äußere Routine nicht |  |
| LR7 | Band an, drei Stufen (Prozedur in Gueltig) | Innerste Routine in ihrer Farbe, die mittlere in ihrer; keine doppelte Überlagerung |  |
| LR8 | Lange Routine scrollen, bis der mitlaufende Kopf `function Gueltig` zeigt | Kopfzeile und Linien im Kopf in derselben Farbe wie im Editor |  |
| LR9 | Unit mit `interface`-Teil mit mehreren Routinen und Klassen | Klassen im interface und Routinen der implementation in der ersten Paarfarbe (keine falsche Stufe) |  |
| LR10 | Paarfarben aus | Keine Farben, kein Band |  |
| LR11 | Englische Oberfläche | Beschriftungen englisch |  |
| LR12 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasPairsTests`, `TAtlasRoutineNestingTests`, Einstellungs- und Seitentests grün |  |
| LR13 | Große Unit, Kopf nicht sichtbar (Anfang einer Routine oben); mit dem Rollrad zügig in kleinen Schritten nach unten und oben scrollen | Blocklinien bleiben durchgehend; keine Bruchstücke spitz auslaufender Linien in den Zeilen über dem unteren Rand |  |

### Ersetzen-Fenster: Knopf wieder sichtbar (#893, PR #1790)

Ergänzt den Abschnitt „Suchleiste: Ersetzen, Regex, Verlauf, Bereiche über Dateien (#893)“.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| ER19 | Wie ER11, Fenster „Atlas-Suche: Ersetzen“ angedockt und frei schwebend, bei 100 % und 150 % Skalierung | Unter der fetten Kopfzeile eine Zeile mit Hinweis links und Knopf „Ausgewählte ersetzen“ rechts in voller Höhe, Beschriftung lesbar; der Knopf bleibt beim Verkleinern des Fensters sichtbar |  |
| ER20 | Wie ER12, danach den Knopf ansehen | Hinweis „n Ersetzungen in m Dateien“ links neben dem Knopf, Knopf sichtbar (ausgegraut, bis die neue Suche Treffer hat), Kopfzeile „Keine Suche über Dateien.“ bzw. die neuen Treffer |  |

### Fenster „Auswerten“ wächst mit (#784, PR #1794)

Ergänzt den Abschnitt „Fenster „Auswerten“ (#784)“.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| AW27 | Fenster frei schwebend öffnen und größer ziehen, dann schmal ziehen und wieder breit; auch angedockt | Kein leerer Streifen unter der Tastenhilfe: Baum (bzw. nach dem Teiler die Ansicht) füllt die Höhe, die Tastenhilfe umbricht schmal auf mehrere Zeilen und wird breit wieder einzeilig |  |
| AW28 | Leiste über der Ansicht ansehen | Links Text, Zeilen, JSON, Hex; rechts Ändern …, Festheften, IDE-Dialog (IDE-Dialog ganz rechts) |  |

### Code Lens der Testklasse (#69, PR #1762)

Ergänzt den Abschnitt „DUnitX-Tests ausführen (#69)“.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| TR25 | Fixture mit vier Tests, nach IDE-Neustart nur einen Test über seine Marke ausführen (bestanden) | Die Marke des Tests „Test ausführen · bestanden“ in Grün; die Marke der Klasse „Tests der Klasse ausführen · 1/4 bestanden“ in Gelb, die übrigen Tests ohne Stand |  |
| TR26 | Danach die anderen drei Tests einzeln ausführen (alle bestanden) | Klassenmarke zählt mit („2/4“, „3/4“) und zeigt nach dem vierten „Tests der Klasse ausführen · bestanden“ in Grün |  |
| TR27 | `[TestCase]`-Methode mit zwei Fällen in eigener Zeile, nur „Fall ausführen“ am ersten Fall | Fallmarke „bestanden“; Marke der Methode „Test ausführen · 1/2 bestanden“ in Gelb; schlägt ein Fall fehl, sind Methode und Klasse sofort „fehlgeschlagen“ |  |

### Leckmeldungen der Tests (Offene Punkte Cloud, Punkt 4)

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| LK1 | `Atlas.Tests` (Win64) vollständig laufen lassen | Alle Tests grün, keine Leckmeldung, `TESTEXIT 0` |  |
| LK2 | Nur die Fixtures `TGoldenCorpusTests`, `TLspClientTests`, `TAtlasTimeLimitTests`, `TAtlasLogRedactorTests`, `TAtlasMainThreadTests`, `TIndexCacheDirectoryTests`, `TLspInlineValuesTests`, `TMcpToolsTests`, `TAtlasSettingsPageTests` einzeln laufen lassen (`--run:`) | Keine Leckmeldung, auch wenn die Fixture als erste läuft |  |
| LK3 | `ForgetStartsNumberingAgain` | Grün |  |

### Englische Texte (#1458)

Englisch über `ui.language` = en bzw. englische IDE; Deutsch zur Gegenprobe über `ui.language` = de.

### Meldungen des Servers zweisprachig (#1458, Gruppe C)

Vorbereitung: AtlasServer und `Atlas.Tests` aus dem Branch gebaut; ein Projekt mit Befunden; MCP-Client (z. B. Claude Code) mit `AtlasServer --mcp`.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| ZE1 | `AtlasServer --check <Projekt> --locale en` | Zusammenfassung, Hinweise und Fehlermeldungen englisch (z. B. „Symbol index: … units in … s“), Befundtexte englisch (**Abnahme**) |  |
| ZE2 | Wie ZE1 mit `--locale de` | Dieselben Ausgaben deutsch wie bisher |  |
| ZE3 | `AtlasServer --check <Projekt> --locale xx --format foo` | Zwei Warnungen in der Sprache aus `settings.json` (ohne `language` englisch): unbekannte Sprache und unbekanntes Format |  |
| ZE4 | `AtlasServer --mcp --locale en`, im Client die Werkzeugliste ansehen | Beschreibungen aller Werkzeuge und Parameter englisch; ein Aufruf ohne Pflichtargument meldet „Argument … is missing“ (**Abnahme**) |  |
| ZE5 | Wie ZE4 mit `--locale de` | Beschreibungen und Meldungen deutsch |  |
| ZE6 | In der IDE mit englischer Oberfläche (`language` = en) eine abgeschaltete Refaktorierung (z. B. `refactoring.safeDelete` aus) auslösen | Meldung englisch „"Safe delete" is turned off (refactoring.safeDelete).“ |  |
| ZE7 | In der IDE mit englischer Oberfläche „Projekt kompilieren“ ohne gültige Lizenz bzw. ohne Projekt | Meldungen des Servers englisch (z. B. „No folder with a project open“) |  |
| ZE8 | `Atlas.Tests` bauen und ausführen (Win64) | 0 Fehler, 0 Warnungen, 0 Hinweise; `TShellTextsTests`, `TCommandLineOptionsTests.WarningTextFollowsLanguage`, `TMcpToolsTests.ToolsSpeakBothLanguages`, `TLocalizationTextsTests.AllTablesComplete` grün; Tests mit deutschen Erwartungen unabhängig von der Reihenfolge grün |  |
| ZE9 | AtlasServer mit Delphi 12 und 13 übersetzen | 0 Fehler, 0 Warnungen, 0 Hinweise |  |
### Texte von Atlas.IDE.Base englisch (#1458, Gruppe D)

Vorbereitung: Win32-Plugin und alle Module gebaut; eigenes Registry-Profil (`bds -r AtlasEn`); englische Oberfläche (`ui.language` = en), IDE neu gestartet.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| BEN1 | Datei mit Encoding UTF-8 ohne BOM öffnen, Statusfeld „Format“ ansehen und anklicken | Format und Menü englisch („UTF-8 without BOM“, „LF“ …), Hinweise beim Speichern englisch („… saved as …“) |  |
| BEN2 | Vervollständigung mit Strg+Leertaste in einer Unit, auch mit Code-Vorlagen (`for`, `try`) | Kennzeichen der Einträge, Vorlagennamen und -beschreibungen englisch |  |
| BEN3 | *Tools › Options › Keyboard* (Tastaturbelegungen der IDE) | Einträge „Atlas completion“ und „Atlas compiler check“ |  |
| BEN4 | Pfad zum Server in den Optionen auf eine nicht vorhandene Datei setzen, IDE neu starten | Meldungsfenster „Server not found: … (the built-in Code Insight stays active)“; Statusfeld „AtlasServer.exe not found“ |  |
| BEN5 | Server im Task-Manager beenden | Hinweis zum Ende englisch (z. B. „exit code unknown …“) |  |
| BEN6 | Doku-Tooltip über einer Routine mit XML-Doku (Parameter, Rückgabe, Ausnahmen) | Überschriften englisch („Parameters“, „Returns“ …) |  |
| BEN7 | Aufrufdiagramm einer Routine öffnen (Rechtsklick › Aufrufhierarchie › Diagramm) | Seitentitel „Call diagram: …“, Schalter, Legende und Hinweis englisch |  |
| BEN8 | Umbenennen eines Ereignisses einer Form, die im Designer offen ist, so dass Atlas ablehnt | Grund englisch („open in the designer; there Atlas only changes …“) |  |
| BEN9 | Atlas-Änderung rückgängig machen, während das Projekt ungespeichert ist | Grund „project has unsaved changes; please save first“ |  |
| BEN10 | Fehlerbericht anlegen (Atlas › Problem melden) und Diagnosefenster öffnen | Texte und Funktionsnamen der Sicherung englisch |  |
| BEN11 | Teamdatei `.atlas` neu anlegen (Optionen › Projekt) | Kommentare im Gerüst englisch, Datei gültig |  |
| BEN12 | Deutsche Oberfläche (`ui.language` = de), BEN1, BEN3 und BEN7 | Wieder deutsche Texte |  |
| BEN13 | `Atlas.Tests` bauen und ausführen; Win32-Plugin und Win64-Gruppe bauen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasTextLanguageTests`, `TAtlasCallDiagramTests.HtmlFollowsLanguage`, `TAtlasServerCrashesTests.DescribesExitCodesInEnglish`, `TAtlasTeamFileTests.SkeletonIsValidInEnglish` grün |  |

### Tracker-, Willkommens- und Debugger-Texte englisch (#1458, Gruppe E)

Vorbereitung: Win32-Plugin und alle Module gebaut; eigenes Registry-Profil (`bds -r AtlasEn`); Projekt in einem Git-Repository mit Tracker-Verbindung (YouTrack oder GitHub).

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| UE1 | Englische Oberfläche (`ui.language` = en), IDE neu starten; Willkommensseite, „My issues“, Board, Issue-Vorschau, Fenster „Evaluate“ und „Exceptions“ öffnen | Alle Überschriften, Knöpfe, Menüs, Hinweise und Meldungen englisch (**Abnahme**) |  |
| UE2 | *Tools › Options › Atlas › Issue tracker*, Tabelle „Snippets“ (nie geändert) | Zwei Bausteine „Please check with the current build“ und „Fixed in {commit}“ |  |
| UE3 | Im Kommentar-Editor der Issue-Vorschau „Snippet ▾“ | Dieselben englischen Bausteine |  |
| UE4 | Feld „Comment when finishing“ (nie geändert); dann ein Issue beenden | Feld zeigt `Done in {branch}.\n{commits}`, der Dialog „Finish …“ schlägt „Done in <Branch>.“ vor |  |
| UE5 | Deutsche Oberfläche (`ui.language` = de), UE2 und UE4 | Wieder „Bitte mit aktuellem Build prüfen“, „Behoben in {commit}“ und `Erledigt in {branch}.\n{commits}` |  |
| UE6 | Einen Baustein umbenennen, OK, Sprache wechseln | Eigene Bausteine bleiben, wie sie sind |  |
| UE7 | Englische Oberfläche: beim Debuggen „Attach to issue …“ mit Debug-Notiz | Anhang heißt `debug-note-JJJJ-MM-TT-hhmm.md` (deutsch `debug-notiz-…`) |  |
| UE8 | Englische Oberfläche: Issue beginnen, Git-Hook erlauben; `.git/hooks/prepare-commit-msg` öffnen | Kommentarzeilen englisch („Created by Atlas …“); Commit bekommt das Präfix wie bisher |  |
| UE9 | Zeitbuchung „Correct …“ mit `2 hours 30 minutes`, dann `1 hour` | Wird als 2:30 bzw. 1:00 übernommen |  |
| UE10 | `Atlas.Tests` bauen und ausführen; Win32-Plugin und Win64-Gruppe bauen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasCommentEditorTests.SnippetDefaultsFollowLanguage`, `TAtlasTrackerWorkflowTests.EndCommentFollowsLanguage`, `TAtlasTrackerSettingsTablesTests.SnippetsDefaultsInLanguage`, `TAtlasCommitHookTests`, `TAtlasDebugNoteTests.FileNameHasDateAndTime` grün |  |

### Englische Texte der übrigen Module (#1458, Gruppe F)

Vorbereitung: Win32-Plugin mit den Modulen Build-Werkzeuge, Build-Pipeline und Tests gebaut; eigenes Registry-Profil (`bds -r AtlasEnglisch`); Git-Projekt mit Testprojekt. Englisch über `ui.language` = en bzw. englische IDE, Deutsch über `ui.language` = de.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| ENF1 | In `atlas.json` des Projekts `"tasks": [{"name": "Lint", "command": "x", "args": 1, "key": "Q"}, {"command": "y"}]` eintragen, Projekt aktivieren; englische Oberfläche | Meldungsansicht (Gruppe Atlas) nennt englisch „Lint: args must be a list“, „Lint: key "Q" not readable“, „tasks[1]: without name“ (**Abnahme**) |  |
| ENF2 | Dasselbe mit deutscher Oberfläche | „Lint: args muss eine Liste sein“, „Lint: Taste "Q" nicht lesbar“, „tasks[1]: ohne name“ wie bisher |  |
| ENF3 | Englische Oberfläche; in Claude Code `build_project` für ein Projekt, das in der IDE nicht offen ist | Antwort „The project X.dproj is not open in the IDE“ |  |
| ENF4 | Englisch; während ein Build in der IDE läuft, `build_project` aufrufen; danach mit laufendem Debugger | „A build or compiler check is already running in the IDE“ bzw. „The debugger is running in the IDE“ |  |
| ENF5 | Englisch; `build_project` mit `mode` = `clean` (über die Auftragsdatei im Eingang) | Antwort „Unknown mode "clean"; allowed are make, build and check“ |  |
| ENF6 | Englisch; `tests.affectedBeforeCommit` an, Hook anlegen lassen (`.git/hooks/pre-commit` vorher löschen); Datei ändern und in Git Bash committen | Hook-Kommentare englisch; Frage „Atlas: Run the affected tests now (test EXE without a new build)? [y/N]“; `y` startet die Tests, nach Fehlschlag „Atlas: Tests failed. Commit anyway? [y/N]“ |  |
| ENF7 | Deutsch; Einstellung aus- und einschalten (Hook neu schreiben), committen | Fragen deutsch mit „[j/N]“; `j` und `y` gelten in beiden Sprachen |  |
| ENF8 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasTaskDefinitionsTests`, `TAtlasTaskTextsTests.IssueInBothLanguages`, `TAtlasBuildInboxTests`, `TAtlasAffectedHookTests` und die Strings-Tests von Build, BuildPipeline und Tests grün |  |

### Texte von Atlas.Common englisch (#1458, Gruppe B, PR #1797)

Im PR heißen die Tests MS1–MS4; hier MSB1–MSB4, damit sie nicht mit den Modulschaltern MS1–MS4 in Teil 4 verwechselt werden.

| Nr. | Schritte | Erwartet | Ergebnis |
|----|----------|-----------|---|
| MSB1 | IDE auf Englisch: Codeaktionen, Hover, Slash-Befehle, Statuszeile ansehen; dann IDE auf Deutsch | Englisch bzw. weiter deutsch |  |
| MSB2 | Englisch: Architekturbericht als HTML speichern, mit gespeichertem Stand vergleichen | Karte und Vergleich mit englischen Texten |  |
| MSB3 | Englisch: Vervollständigung einer nicht eingebundenen Unit | Marke „+ Unit“ wie auf Deutsch |  |
| MSB4 | MCP `get_declaration` mit Begründungen, englisch | „Rationales:“ auf Englisch |  |

### Regeltexte deutsch und englisch (#1458, Gruppe A, PR #1799)

| Nr. | Schritte | Erwartet | Ergebnis |
|----|----------|-----------|---|
| AT1 | Englische IDE, Unit mit einem leeren except-Block | Meldung und Glühbirne englisch („Empty except block swallows every exception…“, „Insert raise;“) |  |
| AT2 | Deutsche IDE, derselbe Fall | Texte unverändert deutsch |  |
| AT3 | Englische IDE, Aufruf eines deprecated-Symbols | Befund ist durchgestrichen |  |

## Teil 6: Neue Funktionen und Korrekturen bis zum 05.11.2026

### Update-Installer (#1519)

Voraussetzung: Release-Paket einer älteren Version (z. B. 2.0.0-beta.1) in `%LOCALAPPDATA%\Programs\Atlas`, eigenes Registry-Profil (`bds -r AtlasUpdate`), `updates.check` an; ein Test-Release mit `atlas-version.json` (bzw. Kanal `update-channel`) einer neueren Version. Protokoll: `%LOCALAPPDATA%\Atlas\Updates\<Version>\update.log`.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| UX1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasUpdateInstallTests`, `TAtlasUpdateInstallUiTests`, `TCommonUpdates*Tests`, `TTextUpdate*Tests` grün; Win64-Gruppe samt `AtlasUpdate` und Win32-Plugin ohne Meldung |  |
| UX2 | Neue Version gefunden, Zeile „Version“ im Statusfeld anklicken | Dialog „Atlas X ist verfügbar“ mit „Beim Beenden installieren“, „Änderungen ansehen“, „Später“ |  |
| UX3 | In UX2 „Beim Beenden installieren“ | Kein Fenster; Zeile „Version“ zeigt „wird vorbereitet (… %)“, danach „wird beim Beenden installiert“; Meldungsansicht „Atlas X ist geprüft und wird beim Schließen der IDE installiert.“; Ordner `Updates\X\files` mit `AtlasServer.exe`, `AtlasUpdate.exe`, `Win32\…` (**Abnahme**) |  |
| UX4 | IDE schließen | Konsolenfenster „AtlasUpdate“ wartet, bis die IDE beendet ist, tauscht und meldet Erfolg; Fenster schließt sich |  |
| UX5 | IDE mit demselben Profil starten | Meldungsansicht „Atlas X installiert (vorher Y).“; *Hilfe › Info* zeigt X; `result.json` und der Ordner `Updates\X` sind weg (**Abnahme**) |  |
| UX6 | Update mit neuem Modul, `updates.newModules = ask`; nach der Vorbereitung auf „Version“ klicken, „Module wählen …“ | Liste mit Häkchen, Kern und Verträge gewählt und grau, neues Modul „(neu)“ nicht gewählt; nach „Übernehmen“ und Schließen der IDE ist das Modul installiert; ein abgewähltes vorhandenes Modul ist entfernt und nicht mehr in den Known Packages |  |
| UX7 | Während UX4 eine zweite IDE mit Atlas aus demselben Ordner offen lassen | Konsole nennt „bds.exe (PID)“ und wartet; nach dem Schließen läuft der Tausch |  |
| UX8 | In UX4 Strg+C, bevor getauscht wird | „abgebrochen“; nächster Start meldet „Atlas-Update X abgebrochen; nichts wurde geändert.“ |  |
| UX9 | Eine BPL im Atlas-Ordner schreibschützen, UX3/UX4 | Konsole meldet den Fehler und nimmt alles zurück, Eingabetaste schließt; nächster Start: „zurückgenommen … Protokoll: …“; die alte Version läuft |  |
| UX10 | Atlas unter `C:\Program Files\Atlas` (nicht beschreibbar), UX3/UX4 | Kein UAC-Dialog; Meldung „der Atlas-Ordner ist nicht beschreibbar; … AppData\Local\Programs\Atlas …“; nichts geändert |  |
| UX11 | In UX2 „Später“, dann `updates.install = auto`, IDE neu starten | Nach einigen Sekunden beginnt die Vorbereitung ohne Frage; bei einer neuen Hauptversion kommt stattdessen der Dialog mit Hinweis auf die Änderungen |  |
| UX12 | `updates.install = off` | Klick auf „Version“ öffnet wie bisher die Änderungen im Browser |  |
| UX13 | Atlas aus dem Repo-Ausgabeordner (`Output\Win32\Debug\Bpl`) bzw. über GetIt | Klick auf „Version“: Meldungsansicht nennt den Grund („kein Release-Ordner“ bzw. „über GetIt“), dann Browser |  |
| UX14 | Vorbereitet, Klick auf „Version“, „Nicht installieren“ | Ordner `Updates\X` weg, beim Schließen keine Konsole |  |
| UX15 | `updates.channel = prerelease` | Abfrage geht an `…/releases/download/update-channel/atlas-version-beta.json`; eine Vorabversion wird angeboten |  |
| UX16 | Delphi 12 mit vollem RAD Studio (MSBuild), Update anbieten lassen | Zeile zeigt „wird aus dem Quelltext gebaut“; danach wie UX3–UX5 mit BPLs `…290.bpl` |  |
| UX17 | Signiertes Release: in `Updates\X\files` eine BPL durch eine unsignierte ersetzen, Vorbereitung erneut | „Datei nicht signiert“ bzw. „Signatur ungültig …“; nichts installiert |  |
| UX18 | `AtlasUpdate.exe install` im entpackten Paket | Fragt IDE und Profil, Ziel (Vorschlag `%LOCALAPPDATA%\Programs\Atlas`) und Module; danach lädt die IDE Atlas ohne Handarbeit; alte Einträge `Atlas.IDE.Expert`/`BetterDelphiLSP` sind aus den Known Packages entfernt |  |
| UX19 | Release-Workflow mit einem Test-Tag | Release enthält `AtlasUpdate.exe` im ZIP, `atlas-ide-expert-source-<Version>.zip`, `atlas-version.json` mit `packages."37.0"` und `source` samt SHA-256; Release `update-channel` (Vorabversion) mit neuer `atlas-version-beta.json` |  |
### Einstellungen nur der installierten Module (05.11.2026)

Vorbereitung: Win32-Plugin und alle Module gebaut; eigenes Registry-Profil (`bds -r AtlasModule`).

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| ME1 | Alle Packages installiert; *Tools › Optionen › Atlas* öffnen | Alle Seiten wie bisher: Debuggen, Release-Build, Willkommensseite, Issue-Tracker; auf „Compiler“ die Schalter von Build-Werkzeugen, Build-Pipeline und Tests; „Units suchen“ mit Suche und Suchleiste |  |
| ME2 | Alle Packages außer `Atlas.IDE.Base` deinstallieren, IDE neu starten, Optionen öffnen | Nur die Einstellungen von Base: keine Seiten Debuggen, Release-Build, Willkommensseite, Issue-Tracker; auf „Compiler“ nur Probleme, Aktion nach dem Speichern und Kosten einer interface-Änderung; „Units suchen“ nur mit Quick Open; „Prüfregeln“ ohne Modulschalter und Sammelkorrektur (**Abnahme**) |  |
| ME3 | In ME2 Seite „Versionsverwaltung“ | Keine Links „Willkommensseite“ und „Issue-Tracker“ |  |
| ME4 | Nur `Atlas.IDE.Debugger` wieder installieren (Komponente › Packages installieren), Optionen öffnen | Seite „Debuggen“ mit Modulschalter und allen Einstellungen des Debuggers; die übrigen Module fehlen weiter |  |
| ME5 | In ME4 einen Wert auf „Debuggen“ ändern, OK, Optionen wieder öffnen | Wert gespeichert; Punkt für geänderte Werte und „Auf Standard zurücksetzen“ im Kontextmenü wie auf den Seiten von Base |  |
| ME6 | Willkommensseite installiert, Issue-Tracker nicht; Seite Willkommensseite › „Meine Issues“ | Neben „Meine Issues“ kein Knopf zur Seite Issue-Tracker; mit installiertem Tracker ist er da und führt dorthin |  |
| ME7 | Werte eines nicht installierten Moduls in der Registry (z. B. `DebugEnabled` = 0); Optionen mit OK schließen, Modul wieder installieren | Der Wert ist unverändert erhalten |  |
| ME8 | Englische Oberfläche (`ui.language` = en), alle Module | Modulschalter auf jeder Seite englisch beschriftet |  |
| ME9 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; die Testklassen `T…SettingsSectionTests` der Module und `TAtlasSettingsSectionTests` grün |  |

### Prüfregeln vollständig im Modul (#1755)

Vorbereitung: Win32-Plugin, `Atlas.IDE.Base` und `Atlas.IDE.Rules` gebaut; eigenes Registry-Profil (`bds -r AtlasRegeln`). Testprojekt mit `atlas.json` und einigen Regelbefunden (z. B. `no-with`, `magic-number`).

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| RM1 | Beide Packages installiert; Fenster „Atlas-Prüfung“, Rechtsklick auf einen Regelbefund | „Für diese Zeile unterdrücken“, „Regel einstellen…“, „Regel abschalten“ und „Regel erklären“ wie bisher; bei einer Compilermeldung sind die drei Regel-Einträge gesperrt |  |
| RM2 | In RM1 „Für diese Zeile unterdrücken“ auf einen Befund in einer nicht geöffneten Unit | Die Unit öffnet sich an der Stelle, über der Zeile steht `// lsp-ignore: <Regel>`, der Befund verschwindet nach der Prüfung |  |
| RM3 | In RM1 „Regel einstellen…“ | Dialog der Projekt-Einstellungen öffnet im Knoten der Gruppe der Regel, die Regel ist in der Tabelle markiert |  |
| RM4 | In RM1 „Regel abschalten“, dann `atlas.json` ansehen | `"<Regel>": "off"` (bei Regeln mit Optionen nur `"severity": "off"`), Kommentare und andere Schlüssel unverändert; Meldung „Regel … in atlas.json abgeschaltet.“ |  |
| RM5 | Ohne Projekt (alles schließen, eine einzelne Unit öffnen) „Regel abschalten“ | Eintrag landet in der globalen `settings.json` |  |
| RM6 | Befund-Hover über einem Regelbefund: „Regel einstellen…“ und „Unterdrücken“ in der Aktionszeile | Wie RM3 bzw. RM2 (gleicher Weg über das Modul) |  |
| RM7 | *Tools › Optionen › Atlas › Prüfregeln*, Hauptknoten | Modulschalter, Hinweis, „Projekt-Prüfregeln bearbeiten …“ und „Globale Prüfregeln bearbeiten …“, darunter „Profile und Baseline“ mit Stand der Baseline, „Baseline neu erzeugen“, „Baseline löschen“, „Unterdrückungen (lsp-ignore) je Regel“ mit „Auswerten“; kein eigener Knoten „Profile und Baseline“ mehr |  |
| RM8 | In RM7 „Baseline neu erzeugen“, dann „Baseline löschen“ (Rückfrage mit Ja) | Stand zeigt „%d Treffer in %d Einträgen“, nach dem Löschen „Keine Baseline im aktiven Projekt“; Datei `atlas-baseline.json` neben `atlas.json` erzeugt bzw. gelöscht |  |
| RM9 | In RM7 „Auswerten“ | Liste je Regel „Regel: Anzahl (ungenutzt …, in … Dateien)“ bzw. „Keine Unterdrückungen“ |  |
| RM10 | Seite *Atlas › Server* | Nur noch Server, Dialoge der Einstellungsdateien und Index-Cache; keine Baseline und keine Unterdrückungen mehr |  |
| RM11 | `Atlas.IDE.Rules` deinstallieren, IDE neu starten; RM1 wiederholen | Nur „Regel erklären“ (und Issue/Kopieren); keine Einträge zum Unterdrücken, Einstellen oder Abschalten; im Hover keine Regel-Aktionen |  |
| RM12 | In RM11 *Atlas › Projekt-Einstellungen* | Dialog ohne Knoten je Regelgruppe; „rules“ als JSON-Text, Änderungen dort werden gespeichert |  |
| RM13 | In RM11 *Tools › Optionen › Atlas › Prüfregeln* | Prüffenster und Compiler-Einstellungen wie bisher; keine Baseline, keine Unterdrückungen, keine Wege zu den Regeln |  |
| RM14 | `Atlas.IDE.Rules` ohne Neustart wieder installieren, RM1, RM7 und RM12 wiederholen | Einträge, Abschnitt und Regel-Editor sind sofort wieder da |  |
| RM15 | Englische Oberfläche (`ui.language` = en), RM1 und RM7 | Alle Einträge, Knöpfe und Meldungen englisch |  |
| RM16 | `Atlas.Tests` bauen und ausführen; Win32-Plugin und Win64-Gruppe bauen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasRulesSettingsDialogTests`, `TRulesSettingsSectionTests`, `TAtlasRuleTableTests`, `TAtlasRuleExplanationTests` und `TAtlasSettingsPageDialogTests.DialogWithoutRulesModuleShowsJson` grün |  |

### Metrik-Lens im Modul Analyse (#1756)

Vorbereitung: Win32-Plugin und alle Module gebaut; eigenes Registry-Profil (`bds -r AtlasModule`); Projekt mit einer Methode über einem Grenzwert (z. B. zyklomatisch > 15), Server läuft.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| LA1 | Alle Packages installiert; Unit mit Methoden öffnen, kurz warten | Marken hinter jedem Methodenkopf, an Klasse, Unit-Namen und uses wie bisher; die Methode über dem Grenzwert gelb mit „(> 15)“ (**Abnahme**) |  |
| LA2 | Cursor in eine Methode setzen | Atlas-Statusleiste zeigt Zeilen und CC der Methode wie bisher |  |
| LA3 | *Tools › Optionen › Atlas › Editor › Code Lens* | Zeile „Code Lens mit Code-Metriken hinter dem Methodenkopf“ unter „Code Lens und Kennzahlen“; ausschalten, OK: die Marken verschwinden sofort, die Statusleiste zeigt weiter Zeilen und CC |  |
| LA4 | Wieder einschalten; dann Modulschalter „Analysefenster“ (`analysis.enabled`) auf *Allgemein* aus, OK | Marken verschwinden ohne Neustart, Statusleiste zeigt weiter Zeilen und CC |  |
| LA5 | `Atlas.IDE.Analysis` deinstallieren (Komponente › Packages installieren), IDE nicht neu starten | Marken verschwinden, keine Fehlermeldung, Statusleiste zeigt weiter Zeilen und CC; in den Optionen fehlt die Zeile der Lens |  |
| LA6 | `Atlas.IDE.Analysis` wieder installieren | Marken erscheinen nach der nächsten Tipp-Pause wieder; im Diagnoselog nur eine Anfrage `atlas.server.metrics` je Textstand, nicht zwei |  |
| LA7 | Schnellschalter (Klick auf das Atlas-Feld) › „Code-Metriken“ aus und an | Marken verschwinden und erscheinen wieder |  |
| LA8 | Marke rechts anklicken › Ausblenden › „Nur hier“ | Nur diese Marke verschwindet; Eintrag in `.atlas` wie bisher |  |
| LA9 | Englische Oberfläche (`ui.language` = en) | Marken englisch („12 lines · depth 2 · …“), Zeile in den Optionen englisch |  |
| LA10 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasAnalysisMetricsLensTests`, `TAtlasEditorMetricsTests`, `TAnalysisSettingsSectionTests.MetricsLensRoundTrip` grün |  |

### Abgebrochene Serveranfragen in 2.0-stable (05.11.2026)

Vorbereitung: großes Projekt bzw. Projektgruppe, Fenster „Atlas-Diagnose“ (Reiter Hauptthread, Server, Hänger) und „Atlas-Server“ offen. Für AA22 bis AA26 ohne eigene große Unit: `node Tools/Benchmark/big-unit.mjs BigUnit.pas` erzeugt eine Unit mit etwa 27.600 Zeilen (600 Methoden mit je drei verschachtelten lokalen Routinen); `--lines L` für etwa L Zeilen, `--routines N` für genau N Methoden, `--depth D` für die Verschachtelungstiefe (0 = keine). Die Unit in ein Projekt aufnehmen und öffnen.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| AA1 | `memoryBudgetMb` auf den bisherigen Wert (z. B. 1024), IDE neu starten, warten bis „bereit“, eine Unit mit vielen public-Methoden öffnen | Fenster „Atlas-Server“: `unused-public-member` nicht mehr unter den langsamsten Regeln mit Minutenwerten; die Warteschlange der Prüfung läuft leer (**Abnahme**) |  |
| AA2 | Im Editor tippen und mit der Maus durch Zeilen klicken, 2 Minuten | Reiter „Hänger“: keine Einträge von 600 bis 800 ms mehr durch Inlay-Hints, Glühbirne, Überschreibungen oder Gliederung; Reiter „Hauptthread“: `InlayHints`, `GutterColumn` und `Outline` mit Maximum unter 50 ms (**Abnahme**) |  |
| AA3 | Cursor auf eine Zeile mit Befund, der eine Schnellkorrektur hat (z. B. fehlendes `begin`/`end`) | Nach kurzer Zeit erscheint die Glühbirne in der Atlas-Spalte am Rand |  |
| AA4 | Eine Klasse mit überschriebenen Methoden öffnen | Überschreibungs-Marker in der Atlas-Spalte erscheinen, ohne dass die IDE stockt |  |
| AA5 | Gliederung (Brotkrümel/Sticky Scroll) in einer großen Unit, während der Server prüft | Gliederung folgt nach der Antwort; im Log höchstens vereinzelt „Gliederung: keine Antwort vom Server (… 5000 ms)“, nicht mehr alle paar Sekunden |  |
| AA6 | Mitteilungen über 30 Minuten Arbeit | Kein „Absturzfall gesichert — Der Server hat die Anfrage abgebrochen: textDocument/codeAction“ mehr |  |
| AA7 | IDE schließen, während der Server beschäftigt ist | IDE schließt ohne Zugriffsverletzung; kein Fehler im Log nach dem Entladen |  |
| AA8 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasBackgroundRequestTests`, `TIndexMemoryTests.KeepsProjectUsagesWhileLibrariesAreEnough`, `TRuleProjectFilesTests.NameInReadsEachFileOnce`, `TRuleFindingsMemoTests` grün |  |
| AA9 | Große Unit öffnen, warten bis die Befunde da sind, mit der Maus durch 20 Zeilen klicken | Fenster „Atlas-Diagnose“, Reiter „Server“: `textDocument/codeAction` im Mittel deutlich unter dem Wert vor dieser Änderung (Messung unter Linux: 0,7–1,5 s → 0,2–0,3 s); Glühbirne erscheint ohne Verzögerung (**Abnahme**) |  |
| AA10 | Mehrere Tabs offen, zehnmal zwischen Tabs wechseln und einmal alle Dateien schließen; danach `atlas.log` ansehen | Je Leiste höchstens eine Zeile „gesperrt (Enabled := False) … weitere Sperren ohne Protokoll“ und eine „wieder freigegeben …“, kein Aufrufstapel; Brotkrümel, Editorleiste und Statusleiste bleiben bedienbar |  |
| AA11 | Fenster „Atlas-Diagnose“, Reiter „Server“, nach einigen Minuten Arbeit | Serverbefehle stehen je Befehl („workspace/executeCommand atlas.server.status“ usw.), nicht mehr alle in einer Zeile |  |
| AA12 | Domänenkonto (Arbeitsrechner), Willkommensseite oder „Atlas-Start“ offen, einige Minuten arbeiten; dann Fenster „Atlas-Diagnose“, Reiter „Hauptthread“ | Willkommensseite ohne Aufrufe über 16 ms im 5-s-Takt, Max. deutlich unter 8,3 s; der Gruß zeigt nach kurzer Zeit den Vornamen (vorher kurz den Kontonamen) |  |
| AA13 | Willkommensseite bzw. „Atlas-Start“ offen und geschlossen, je einige Minuten ohne Projektwechsel arbeiten; dann Fenster „Atlas-Diagnose“, Reiter „Hauptthread“ | Willkommensseite ohne Aufrufe im Sekundentakt; in „Langsame Aufrufe“ keine Willkommensseite mehr alle 1–2 s (**Abnahme**) |  |
| AA14 | Karte „<Projekt> für Atlas einrichten“ sichtbar: anderes Projekt der Gruppe aktivieren (Doppelklick in der Projektverwaltung), dann Projekt schließen, dann anderes Projekt öffnen | Die Karte nennt jeweils sofort das neue Ziel (ohne Projekt das oberste aus „Wieder öffnen“) |  |
| AA15 | Server indiziert, Willkommensseite offen; Thema der IDE wechseln, Sprache bzw. `welcomePage.greeting` umschalten | Kurzstatus zählt weiter mit; nach Thema, Sprache und Schalter stimmen Symbol, Gruß und Texte sofort |  |
| AA16 | Fenster „Atlas-Diagnose“ in der Startgröße bzw. schmal ziehen, dann breit ziehen | Schmal: Knöpfe Anhalten, Zurücksetzen, Bericht kopieren in einer zweiten Zeile rechts, Verlauf und „Langsam ab … ms“ ganz sichtbar; breit: wieder eine Zeile |  |
| AA17 | Server läuft, Diagnosemodus an; eine Unit mit Testunit und Metriken öffnen, tippen, Datei wechseln, Rekursionssymbole an (editor.recursionMarkers); dann Fenster „Atlas-Diagnose“, Reiter „Server“ | Bei `atlas.server.testUnit`, `atlas.server.metrics` und `atlas.server.recursion` „Hauptthread gewartet“ 0; Lens „→ Testunit“, Metriken in der Statusleiste und ↻ erscheinen wie vorher nach der Tipp-Pause |  |
| AA18 | Wie AA17, während der Server indexiert bzw. nach „Server neu starten“ | Kein Stocken; die Lens und die Symbole kommen nach dem Indexieren bzw. Neustart wieder, keine Zugriffsverletzung beim Neustart oder Schließen der IDE |  |
| AA19 | Diagnosemodus an; in einer sehr großen Unit (über 20.000 Zeilen) tippen, scrollen, Datei wechseln, Lesezeichen und Rekursionssymbole an | Tippen flüssig; Lens, Rand, Lesezeichen erscheinen nach der Tipp-Pause wie vorher; nach dem Speichern in einem anderen Editor stimmen die Marken |  |
| AA20 | Fenster „Compiler-Schalter“ zu und Statusfeld der Schalter aus, eine Minute arbeiten; dann Fenster öffnen | Im Reiter „Hauptthread“ wachsen die Aufrufe von „Compile-Ereignisse“ ohne Build nicht mehr um 20 je Sekunde; das Fenster füllt sich sofort |  |
| AA21 | Zwei große Formulare im Designer offen, im einen eine Komponente verschieben | Nur dieses Formular geht an den Server (Diagnoselog); „Formulare“ im Hauptthread deutlich unter 187 ms; Umbenennen eines Handlers in beiden Formularen wirkt weiter |  |
| AA22 | Server mit diesem Stand; die größte Unit des Projekts (über 30.000 Zeilen) öffnen und einige Minuten darin arbeiten | Keine Mitteilung „Absturzfall gesichert – Der Server hat die Anfrage abgebrochen: textDocument/codeAction bzw. textDocument/diagnostic“; Fenster „Atlas-Prüfung“ zeigt die Befunde der Unit spätestens einige Sekunden nach der Tipp-Pause (**Abnahme**) |  |
| AA23 | Wie AA22, Task-Manager offen | AtlasServer.exe fällt nach der Prüfung wieder auf etwa 0 % CPU; kein dauernder Lauf je Cursorbewegung; Speicher wächst nicht weiter |  |
| AA24 | Wie AA22: Cursor auf Zeilen mit und ohne Befund, Hover über Bezeichner | Glühbirne erscheint (während einer laufenden Prüfung höchstens nach etwa 1,5 s, dann ohne Regelkorrekturen); Hover erscheint; Fenster „Atlas-Diagnose“, Reiter „Server“: `textDocument/codeAction` ohne Zeitlimit |  |
| AA25 | Während die Prüfung von AA22 läuft, weiter tippen | Die Befunde folgen dem neuen Stand; kein alter Stand bleibt stehen |  |
| AA26 | Wie AA22, nach Ende der Prüfung: Cursor mit den Pfeiltasten durch die Unit bewegen, auch in Klassendeklarationen mit Get-/Set-Methoden und auf String-Literalen | Glühbirne folgt dem Cursor ohne spürbare Verzögerung; „Property aus Zugriffsmethoden“, „Als Klartext kopieren“ und uses-Aktionen erscheinen wie bisher; Fenster „Atlas-Diagnose“, Reiter „Server“: `textDocument/codeAction` deutlich unter 1 s |  |
| AA27 | Fenster „Atlas-Diagnose“ in der Startgröße öffnen, Reiter „Server“; danach schmaler und breiter ziehen | Spalte „Anfrage“ zeigt `textDocument/codeAction` lesbar; alle Spalten enden am rechten Rand (keine abgeschnittene Spalte); breit wieder volle Breiten |  |
| AA28 | Große Unit (`node Tools/Benchmark/big-unit.mjs --lines 30000`) mit Editor- und Statusleiste öffnen, einige Zeilen tippen und nach jeder Pause kurz warten; dann „Atlas-Diagnose“, Reiter „Hauptthread“ | Tippen ohne Stocken; Editorleiste markiert den Abschnitt am Cursor richtig (interface, implementation, uses), Statusleiste zeigt Befundzahlen und Methode; Statusleiste und Editorleiste ohne Aufrufe über der Schwelle |  |
| AA29 | Projekt mit `.atlas` öffnen, die Datei außerhalb der IDE ändern; dann eine neue `.atlas` eine Ebene höher anlegen (die alte löschen); Projekt wechseln | Änderung gilt nach etwa 2 s; die neue Datei weiter oben gilt nach höchstens etwa 10 s; nach dem Projektwechsel sofort die Datei des neuen Projekts; „Einstellungen“ im Diagnose-Fenster ohne Aufrufe über der Schwelle |  |

### Aktualisierung der Prüfung einstellbar (problems.update)

Vorbereitung: uKundeForm mit einigen Befunden geöffnet, Fenster „Atlas-Prüfung“ offen, Statusleiste an.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| LV1 | *Tools › Optionen › Atlas › Prüfregeln* ansehen | Auswahl „Offene Datei prüfen:“ mit „Live beim Tippen“, „Beim Speichern“, „Nur auf Anforderung“ und Feld „Verzögerung der Live-Prüfung in ms (100 bis 10000):“ mit 400; beide gesperrt, wenn die Prüfregeln aus sind |  |
| LV2 | Live, Verzögerung 2000, OK; tippen und anhalten | Die Liste ändert sich erst etwa 2 s nach dem letzten Tastendruck; mit 100 fast sofort (**Abnahme**) |  |
| LV3 | Verzögerung 50 bzw. 50000 eingeben, OK, Dialog wieder öffnen | Wert auf 100 bzw. 10000 begrenzt |  |
| LV4 | „Beim Speichern“; tippen, dann Strg+S | Beim Tippen keine Prüfung; nach dem Speichern die neuen Befunde |  |
| LV5 | „Nur auf Anforderung“; Datei öffnen, tippen, speichern | Beim Öffnen einmal geprüft, danach weder beim Tippen noch beim Speichern; Klick auf „manuell · …“ in der Atlas-Statusleiste prüft sofort (**Abnahme**) |  |
| LV6 | In LV5 Befehlspalette (Strg+Umschalt+P) › „Datei jetzt prüfen“ | Die offene Datei wird geprüft; mit ausgeschalteten Prüfregeln fehlt der Befehl |  |
| LV7 | In LV5 Klick auf „manuell · …“ in der Statusleiste | Nur die offene Datei wird geprüft; im Live-Modus prüft der Klick weiter alle Units neu (ASL7a) |  |
| LV8 | Einstellungen einer älteren Version mit „Live-Prüfung“ aus (Registry `ProblemsLive` = 0) übernehmen bzw. eine exportierte Datei mit `"problems.live": false` importieren | Danach „Beim Speichern“; mit `ProblemsLive` = 1 bzw. `true` „Live beim Tippen“ |  |
| LV9 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasProblemsRefreshTests`, `TAtlasPluginSettingsTests.ProblemsUpdateOptions`, `ImportMigratesProblemsLive`, `LiveHintsFollowUpdateMode` grün |  |

### Tastenkürzel für „Datei jetzt prüfen“ (#1744)

Vorbereitung: uKundeForm mit einigen Befunden geöffnet, Fenster „Atlas-Prüfung“ offen, `problems.update` = „Nur auf Anforderung“.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| DP1 | *Tools › Optionen › Atlas › Befehle* ansehen | Zeile „Datei jetzt prüfen“ direkt unter „Fenster „Atlas-Prüfung““ mit Strg+Umschalt+Alt+P |  |
| DP2 | Im Editor tippen (Befund erzeugen), dann Strg+Umschalt+Alt+P | Die offene Datei wird sofort geprüft, der neue Befund erscheint im Fenster und im Editor, ohne zu speichern (**Abnahme**) |  |
| DP3 | „Beim Speichern“ einstellen, tippen, Strg+Umschalt+Alt+P | Sofort geprüft, ohne Strg+S |  |
| DP4 | „Live beim Tippen“ mit Verzögerung 5000, tippen, sofort Strg+Umschalt+Alt+P | Geprüft, ohne die 5 s abzuwarten |  |
| DP5 | Feld leeren, OK; Strg+Umschalt+Alt+P im Editor | Atlas reagiert nicht mehr; Befehlspalette und Knopf prüfen weiter |  |
| DP6 | Kürzel Strg+Alt+F9 eintragen (schon „Prüfen“), *Atlas › Tastenkürzel-Übersicht…* öffnen | „Datei jetzt prüfen“ steht rot als Konflikt mit „Prüfen“; mit Strg+Umschalt+Alt+P wieder ohne Konflikt |  |
| DP7 | Prüfregeln ausschalten (`problems.enabled` aus), Strg+Umschalt+Alt+P | Nichts passiert, die Tastenkürzel-Übersicht zeigt die Zeile als abgeschaltet; Eintrag im Editor-Kontextmenü (Atlas-Untermenü) fehlt |  |
| DP8 | Rechtsklick im Editor › Atlas | Eintrag „Datei jetzt prüfen“ unter „Vorheriger Befund“ mit dem Kürzel daneben; Befehlspalette zeigt das Kürzel neben „Datei jetzt prüfen“ |  |
| DP9 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasPluginSettingsTests.CheckFileKeyOption`, `TAtlasKeyMapTests.CheckFileKeyFollowsProblems`, `TAtlasSettingsPageEditorTests.CheckFileKeyRoundTrip`, `EveryKeySettingIsInOverview` grün |  |

### Prüfregel unused-uses (#1135)

Vorbereitung: Projekt mit Unit `uBericht.pas`, deren uses `System.SysUtils, System.Classes, Vcl.Grids` enthält und nur `Format` aus SysUtils verwendet; Fenster „Atlas-Prüfung“ offen.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| UU1 | uBericht im Editor öffnen | `System.Classes` und `Vcl.Grids` abgeblendet, Tooltip „Aus Vcl.Grids wird nichts verwendet“; keine zweite Meldung mit `unused-uses` im Prüffenster (**Abnahme**) |  |
| UU2 | `AtlasServer --check <Projekt> --rules unused-uses`, danach dasselbe mit `--no-index` | Mit Index je ein Hinweis `unused-uses` für die beiden Units; ohne Index nichts |  |
| UU3 | Claude Code: MCP `get_diagnostics` für uBericht.pas | Dieselben zwei Hinweise wie in UU2 |  |
| UU4 | Schnellkorrektur „Eintrag entfernen“ in der Ausgabe von `get_diagnostics` bzw. `--fix unused-uses` | Eintrag samt Komma entfernt, Datei übersetzt weiter |  |
| UU5 | In atlas.json `"rules": {"unused-uses": "off"}`, Datei neu öffnen | Kein Abblenden mehr, `--check` meldet nichts; „uses aufräumen“ entfernt weiter |  |
| UU6 | `"rules": {"unused-uses": {"severity": "warning", "keep": ["Vcl.Grids"]}}` | Vcl.Grids nicht mehr abgeblendet, `--check` meldet nur System.Classes als Warnung; „uses aufräumen“ lässt Vcl.Grids stehen |  |
| UU7 | `"rules": {"unused-uses": {"severity": "hint", "exclude": ["uBericht"]}}` | Kein Abblenden in uBericht, `--check` meldet dort nichts; andere Units unverändert |  |
| UU8 | `// lsp-ignore: unused-uses` in eine eigene Zeile über `Vcl.Grids` schreiben, speichern (mit „Beim Speichern korrigieren“ an) | Vcl.Grids nicht mehr abgeblendet; kein Hinweis `unused-suppression`, der Kommentar bleibt nach dem Speichern stehen; `--check` meldet Vcl.Grids nicht |  |
| UU9 | `--check` mit `--baseline`, in der der Treffer für Vcl.Grids steht | Nur System.Classes gemeldet |  |
| UU10 | *Tools › Optionen › Atlas › Prüfregeln*, Regel „Ungenutzte Unit im uses“ öffnen | Schweregrad wählbar, Option „keep“ als Liste; Änderung wirkt wie UU5/UU6 |  |
| UU11 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TUnusedUsesTests` und `TLspSyntaxDiagnosticsTests.UnusedUsesFollowRule` grün |  |

### Formulardatei verweist auf ein Modul ohne uses (dfm-reference-unit-missing)

Voraussetzung: Server läuft in der IDE mit einem VCL-Projekt aus `Unit1` (`Form1` mit `TFDConnection` `Connection`) und `Unit2` (`Form2` mit `TFDQuery` `Query`); beide stehen in der .dpr.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| FV1 | In `Unit2.dfm` (Text) bei `Query` `Connection = Form1.Connection` eintragen, `Unit1` steht in keiner uses-Liste von `Unit2` | Warnung `dfm-reference-unit-missing` am Feld `Query`: „Connection = Form1.Connection: Form1 stammt aus Unit1, die Unit steht nicht in den uses. …“; im Befund-Hover der Zusatz zur Laufzeit und die Zeile der .dfm als weitere Stelle (**Abnahme**) |  |
| FV2 | Schnellkorrektur „uses Unit1 ergänzen“, danach Strg+Z | `uses Unit1;` nach `implementation`, keine Meldung mehr; ein Undo-Schritt |  |
| FV3 | `Unit1` im interface-uses bzw. vorhandenes implementation-uses | Keine Meldung; die Korrektur hängt `Unit1` an eine vorhandene implementation-Liste an |  |
| FV4 | Verweis auf ein Datenmodul (`DataSet = DM.Query1`, .dpr: `{DM: TDataModule}`), auf das eigene Formular (`Form2.Edit1`), auf einen eingebetteten Rahmen (`Frame11.DataSource1`) und auf ein unbekanntes Modul | Meldung nur beim Datenmodul ohne uses |  |
| FV5 | `Unit1` liegt in einem anderen Projekt der Gruppe (nicht in der .dpr), `Form1: TForm1` im interface | Meldung mit Sicherheit mittel (über den Index) |  |
| FV6 | `"dfm-reference-unit-missing": "off"`, `"group:forms": "off"` bzw. `exclude` | Keine Meldung |  |
| FV7 | Abgleich: FV1 ohne Korrektur, IDE neu starten, nur `Unit2` öffnen und das Formular speichern | Die IDE fragt nach `Unit1` bzw. `Connection` ist leer und fehlt nach dem Speichern in der .dfm; nach FV2 bleibt der Verweis erhalten |  |

### Diagnosepaket und Logs vollständig anonym (#1478)

Vorbereitung: Testprojekt mit Markernamen, z. B. Ordner `C:\MarkerOrdner\MarkerKunde`, Projekt `MarkerKunde.dproj`, Unit `uMarkerLager.pas` mit `TMarkerForm.Geheim` und einem Syntaxfehler; Windows-Benutzer bekannt. Atlas mit Vorgaben (anonym), Server mit `--log`.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| AL1 | Projekt öffnen, Unit bearbeiten und speichern, einen Build mit Fehler auslösen, dann `atlas.log` (`%LOCALAPPDATA%\Atlas\Logs`) öffnen | Kein Markername, kein Pfad, kein Benutzername, kein Quelltext; Namen als `name#N`, Dateien als `datei#N.pas`, Meldungen als `text#N`; gleiche Werte tragen dieselbe Nummer |  |
| AL2 | Server-Log (`--log`) und `diag-*.log` desselben Laufs öffnen | Keine Markernamen; Projekt und Units als `name#N`, Dateien als `datei#N.pas`, Meldungen als `wert#N`; Zahlenzeilen `index project#N … mem X MB` unverändert |  |
| AL3 | *Atlas › Hilfe und Diagnose › Problem melden…*, Vorschau ansehen, ZIP anlegen und entpacken | Die Vorschau zeigt jede Datei; in keiner steht ein Markername, Pfad oder Benutzername; `atlas-info.txt` nennt „Protokoll des Plugins anonym geschrieben“; `einstellungen.json` enthält nur Schlüssel, Zahlen, Schalter und feste Werte (sonst `"<wert>"`, Pfade `"<pfad>"`) (**Abnahme**) |  |
| AL4 | Fenster „Atlas-Server“ › Diagnosepaket | Vorschau beginnt mit „Dateien im Paket:“ und der Liste mit Größen; `fehlerbericht.md`, `server/status.json`, `server/protokoll.txt` ohne Markernamen; Arbeitsbereich und Projekt als `name#N`/`datei#N.dproj` |  |
| AL5 | *Atlas › Fehlerbericht erstellen…* (anonym) | Kopf „· anonymisiert“; Einstellungen nur mit festen Werten; Plugin- und Serverprotokoll ohne Markernamen; unter dem Projekt nur `<ws>/<datei>.pas` |  |
| AL6 | Optionen › Fehlerbericht: „anonymisieren“ aus, Bericht erneut erstellen | Kopf „· mit Klarnamen (ausdrücklich gewählt)“; Namen und Pfade im Klartext |  |
| AL7 | Optionen › Fehlerbericht: „Protokoll atlas.log mit Klarnamen schreiben“ an, Fehler auslösen, `atlas.log` ansehen; dann Bericht und Problem melden | Neue Zeilen im Klartext; der Bericht nennt „geschrieben mit Klarnamen (diagnostics.log.names)“, `atlas-info.txt` ebenso; nach dem Ausschalten wieder `name#N` |  |
| AL8 | `AtlasServer --check <Ordner> --timings` und `--timings profil.json`, danach mit `--log-names` | Ohne `--log-names` Units als `name#N` mit Hinweis „anonymisiert“ bzw. `"anonymized": true`; mit `--log-names` im Klartext |  |
| AL9 | Ausgabefenster der IDE (Meldungen von Atlas) beim selben Lauf ansehen | Meldungen im Klartext ohne Kästchen oder fremde Zeichen (die Kennzeichen erscheinen nirgends) |  |
| AL10 | Prozesse am Projekt (*Atlas › Hilfe und Diagnose*) und danach das Server-Log | Fenster im Klartext; im Log stehen Arbeitsbereich und Cache als `name#N`/`datei#N` |  |
| AL11 | `Atlas.Tests` mit Delphi 12 und 13 bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAnonymityTests`, `TLogMarksTests`, `TAtlasLogRedactorTests`, `TTextAnonymizerTests` grün |  |

### Zeit bis „bereit“ bei Projektgruppen (#1479)

Vorbereitung: Testgruppe mit 8 Projekten, Index-Cache vorhanden, Diagnoselog an (`diagnostics.log`, Vorgabe). Zwei Fassungen: vor 38205b4e (z. B. 1.1.x) und dieser Stand. Je Fassung einen leeren Ordner für die Logs.

| Nr. | Schritte | Erwartet | Ergebnis |
|---|---|---|---|
| ZB1 | Fassung „vor“ installieren; sechsmal: IDE frisch starten, Gruppe öffnen, warten bis die Statusleiste „bereit“ zeigt, Gipfel und Speicher im Fenster „Atlas-Server“ notieren, IDE schließen; die neue `diag-…log` aus `%LOCALAPPDATA%\Atlas\Logs\Diagnose` in den Ordner „vor“ kopieren | Sechs Dateien, jede mit `index project#0 start` … `index project#7 done` |  |
| ZB2 | Dasselbe mit diesem Stand, Logs in den Ordner „nach“; der erste Lauf ist der Umstieg | Sechs Dateien |  |
| ZB3 | `node Tools/Benchmark/ready.mjs --logs vor=<Ordner vor> --logs nach=<Ordner nach>` | Tabelle mit Umstieg, Median und Spannweite je Fassung; „nach“ nicht langsamer als „vor“ (**Abnahme**, Tabelle ins Issue #1479) |  |
| ZB4 | Dieselbe Gruppe ohne IDE: `node Tools/Benchmark/ready.mjs --server vor=<alte AtlasServer.exe> --server nach=<neue> --target <Gruppenordner> --runs 6 --cache %TEMP%\atlas-ready` | Wie ZB3; die Zeiten liegen unter denen der IDE (ohne Start von Delphi) |  |
| ZB5 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TIndexCacheDirectoryTests.OwnLockKnownInProcess` grün |  |

### Korrekturen aus release/1.2

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| R12-1 | Delphi 12: Datei öffnen, Strg+F dreimal hintereinander (Leiste schließen und wieder öffnen) | Suchleiste erscheint jedes Mal; kein „Element ‚TAtlasSearchBar‘ hat kein übergeordnetes Fenster“ im `atlas.log`, keine Meldung „Atlas-Suche abgeschaltet“ (**Abnahme**) |  |
| R12-2 | Profil, in dem 1.1 oder 1.2 lief (Registry-Wert `ProblemsList` = 1), mit 2.0 starten und kompilieren | Keine Liste „Atlas-Probleme“ im Meldungsfenster; unter *Tools › Optionen › Atlas › Prüfregeln › Prüffenster* lässt sie sich wieder einschalten |  |
| R12-3 | Projektgruppe mit 8 Projekten und gemeinsamen Suchpfaden öffnen, bis „bereit“ warten, Fenster „Atlas-Server“ | Bereich „Packages (.dcp)“ einmal statt je Projekt; „Rest“ deutlich unter 1.2.0; Ordner `Index\<Version>\Suchpfade` angelegt |  |
| R12-4 | Wie R12-3, IDE neu starten | Laden aus dem Cache schneller als beim ersten Mal; die Projekt-Caches enthalten keine Suchpfad-Units mehr |  |

## Teil 7: Rauchtests der umgebauten Bereiche

Für die Behebung der Atlas-Befunde (Metriken) wurden viele Units zerlegt, ohne Verhalten zu ändern. Die meisten VCL- und ToolsAPI-Teile sind nur unter FPC bzw. mit Atlas geprüft. Je Zeile genügt ein kurzer Durchgang: Funktion aufrufen, nichts fehlt, keine Ausnahme im `atlas.log`.

| ID | Bereich | Schritte | Ergebnis |
|----|---------|----------|---|
| RT1 | Optionsdialog | Alle Seiten unter *Tools › Optionen › Atlas* öffnen; je Seite einen Wert ändern, OK, IDE neu starten, Wert prüfen; Filter, „Auf Standard zurücksetzen“, Markierung geänderter Werte, Export und Import der Einstellungen, Profile |  |
| RT2 | Einstellungsdialog des Projekts | Seiten, Regelgruppen, „Regel einstellen …“, Zurücksetzen, OK mit Prüfung; Schnellschalter |  |
| RT3 | Vervollständigung | Strg+Leertaste in Code, nach Punkt, in uses, mit Snippets, Live-Vorlagen und Platzhaltern; Detailfeld und Vorschau; Postfix-Vorlagen; inherited-Aufrufe; Parameter-Hint |  |
| RT4 | Hover und Navigation | Hover über Typen, Methoden, Konstanten; Strg+Klick; Gliederung mit Filter; Befehlspalette, Strg+P |  |
| RT5 | Editor | Mehrere Einfügemarken (Tasten, Strg+K, Alt+Klick, Rückgängig), Änderungsmarken und Zeilenhistorie, Bezeichner mitziehen, Minimap, Klammerpaare, Statusleiste und Editorleiste |  |
| RT6 | Code-Aktionen und Umbauten | Alt+Enter an Befunden; Methode anlegen, Extrahieren, Interface/Oberklasse herauslösen, Klasse verschieben, Methode ohne Self, Inline, Variable befördern, Umbenennen; Umbaudialoge |  |
| RT7 | Tastenbindungen | F3 mit Markierung, Strg+W, Zeilen verschieben und duplizieren, Tastenkürzel-Übersicht, Kontextmenü Atlas im Editor |  |
| RT8 | Prüfung | Fenster „Atlas-Prüfung“, Befunde im Editor, Projektprüfung mit Fortschritt, Sammelkorrektur, Baseline aktualisieren |  |
| RT9 | Ergebnisfenster | Verwendungen, Aufrufhierarchie, Typhierarchie: alle Listen, Doppelklick, Filter |  |
| RT10 | Suche | Suchleiste mit Ersetzen, Regex, Verlauf; Fenster „Units suchen“; Fenster „Atlas-Abfrage“ mit gespeicherten Abfragen |  |
| RT11 | Analyse | Fenster Architektur, Hotspots, Abhängigkeiten, Unit-Beziehungen; Bericht speichern |  |
| RT12 | Debugger | Werte im Hover und Editor, Fenster „Auswerten“ (F8 bei 20 Ausdrücken flüssig, AW23–AW26 in `docs/Atlas-Testfaelle.md`), Exception-Leiste und -Verlauf, Schrittfilter |  |
| RT13 | Willkommensseite | Weiterarbeiten samt Fortsetzen und Gemerkt, Schnellaktionen mit Tastatur und Kontextmenü, Einrichten mit atlas.json, Baseline, Seite anpassen mit Ziehen und Scrollen am Rand, Kacheln der Module |  |
| RT14 | Issue-Tracker | Meine Issues, Issue-Vorschau mit allen Reitern, Board samt Verschieben (BO25–BO30 in `docs/Atlas-Testfaelle.md`), Anhängen-Dialog, Kommentarfeld, Zeilenhistorie mit Issue-Kennungen, GitHub und YouTrack |  |
| RT15 | Lesezeichen und Notizen | Schnelle und benannte Lesezeichen, Notizen, TODO-Liste |  |
| RT16 | Code Insight laden/entladen | Package `Atlas.IDE.Base` in *Komponente › Packages installieren* ab- und wieder anwählen, ohne Neustart der IDE; danach Vervollständigung |  |
| RT17 | Fenster „Atlas-Server“ und Diagnose | Speicherbalken, Tabellen, Knopfleiste; Diagnosemodus und Fenster „Atlas-Diagnose“ (DM16–DM26 in `docs/Atlas-Testfaelle.md`) |  |
| RT18 | IDE beenden | Mit offenen Fenstern aller Module, laufendem Index und Debug-Sitzung beenden: keine Zugriffsverletzung, Protokoll ohne „nicht sauber abgemeldet“ (**Abnahme**) |  |

## Teil 8: Release

| ID | Schritte | Erwartung | Ergebnis |
|----|----------|-----------|---|
| RL1 | UX19 aus Teil 6 mit einem Test-Tag (z. B. `v1.9.0-test.1`) in einem Fork oder vor `v2.0.0-beta.1` | Release als Vorabversion; ZIP mit `AtlasServer.exe`, `AtlasUpdate.exe`, Base und elf Modulen je Win32 und Win64, Map-Dateien, `whatsnew.json`, `tips.json`, `Doku`; dazu Quelltext-ZIP und `atlas-version.json`; `atlas-version-beta.json` im Release `update-channel` |  |
| RL2 | Release-Notizen auf der Release-Seite lesen | Deutsch und Englisch aus `docs/Release-Notizen/2.0.0-beta.1.md`, ohne whatsnew-Markierungen |  |
| RL3 | ZIP auf einem Rechner ohne Atlas entpacken, `AtlasUpdate.exe install` | Wie UX18; Karte „Neu in Atlas“ zeigt sieben Karten für 2.0.0-beta.1, bei englischer IDE englisch |  |
| RL4 | Installation mit 1.2.0: Update-Prüfung | Bietet die Beta nicht an (Vorabversion zählt nicht als „latest“) |  |

