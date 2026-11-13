# Bauen, Testen, Debuggen

Zurück zum [README](../../../README_DE.md)

## Bauen

### Schranke für Hinweise und Warnungen

- Zusammenfassung nach jedem Build („erfolgreich, aber 2 Warnungen, 1 Hinweis“)
- wahlweise gilt ein Build mit Warnungen oder Hinweisen als gescheitert
- bekannte Altlasten kommen in die Basislinie

Einstellungen: `build.zeroHints`, `build.warningsAsErrors`

### Ohne Kommandozeilen-Compiler (Starter, Community)

- Beim Start sieht Atlas im Ordner der Installation nach, ob `dcc32.exe` oder `dcc64.exe` da sind (#1822); RAD Studio Starter und je nach Version Community haben keinen Kommandozeilen-Compiler
- das Ergebnis steht in der Startzeile von `atlas.log` („command-line compiler: …“)
- fehlt er, kommt einmal ein Hinweis mit Knopf *Einstellungen*; die Karte „Projekt für Atlas einrichten“ der Willkommensseite nennt es ebenfalls
- Builds für KI-Assistenten (`build_project`) laufen ohnehin über den Compiler der IDE und gehen weiter
- Projektaufgaben, die `dcc32`, `dcc64`, ein anderes `dcc…` oder `msbuild` aufrufen, starten dann nicht, sondern nennen den Grund; Aufgaben, die den Compiler über ein Skript aufrufen, erkennt Atlas nicht

Einstellung: `diagnostics.editionCheck` (aus = Verhalten wie vorher)

### Compilerwarnung gezielt abschalten

- Code-Aktion auf einer Warnung oder einem Hinweis des letzten Builds setzt `{$WARN SYMBOL_DEPRECATED OFF}` … `ON` (bzw. `{$HINTS OFF}`) um die Zeile, die Routine oder die Unit
- auf Wunsch mit Begründung als Kommentar
- oder schaltet die Warnung in den Projektoptionen ab

Einstellungen: `refactoring.disableWarning`

### Schnellkorrekturen für Compilermeldungen

| Meldung | Korrektur |
|---|---|
| H2443 | trägt die fehlende Unit ein |
| E2003 | bietet die Units mit dem Bezeichner an |
| H2077 | entfernt eine wirkungslose Zuweisung (ein Aufruf bleibt) |
| W1035 | fügt `Result := Default(T);` ein |
| W1057/W1058 | setzen eine explizite String-Umwandlung |

„Alle in der Datei beheben“ in einem Rückgängig-Schritt.

Einstellungen: `refactoring.compilerFixes`

### Unit nicht gefunden

- Bei F2613/F1026 sucht Atlas im Projektordner, in der Projektgruppe, in den anderen Konfigurationen, in den Bibliotheken anderer Plattformen und im Index.
- Es bietet an, den Ordner in den Suchpfad dieser oder aller Konfigurationen aufzunehmen (relativ zur `.dproj`) oder die Unit ins Projekt.
- Sonst „nur für Win32, Win64“ bzw. die durchsuchten Orte.

Einstellungen: `refactoring.missingUnit`

### Vor und beim Bauen

- **Prüfung vor dem Kompilieren:** prüft vor jedem Build die seit dem letzten erfolgreichen Compile geänderten Units auf Syntaxfehler und Regelfehler; melden oder Build abbrechen (`build.gate`)
- **Release-Build-Wächter:** prüft vor einem Release-Build die Projektoptionen (DEBUG-Symbol, Debug-Informationen, …)
- **Beim Öffnen einmal bauen**, sobald die IDE ruhig ist:
  - auf Wunsch immer mit derselben Konfiguration und Zielplattform (etwa Debug/Win64), egal was im Projekt eingestellt ist
  - danach steht das Projekt wieder wie vorher
- **Laufendes Programm vor dem Build beenden:** Läuft die exe noch außerhalb des Debuggers, fragt Atlas vor dem Compile „AtlasDemo.exe läuft noch. Beenden und bauen?“ (Ja, Nein, Immer), statt den Build erst am Ende mit F2039 scheitern zu lassen. Beendet wird erst freundlich, nach 2 s hart; Programme im Debugger bleiben unberührt. Bei einem Package nennt ein Hinweis die Programme, die die BPL noch geladen haben (`build.stopRunningProgram`: ask, always, never)

<a id="window-atlascompilerswitches"></a>
### Compiler-Schalter an der Cursorposition

- Ein andockbares Fenster zeigt die wirksamen Schalter `R`, `Q`, `O`, `C`, `I`, `A`, `HINTS`, `WARNINGS`, abgeschaltete Warnungen und aktive Symbole an der Cursorposition.
  - jeweils mit Herkunft (Projektoption, Compiler-Vorgabe, Include-Datei oder Direktive mit Zeile, etwa `R−, gesetzt in Zeile 10`)
  - dazu Plattform und Konfiguration
- Werte, die von der .dproj abweichen, sind hervorgehoben.
- Doppelklick springt zur Direktive oder öffnet die Projektoptionen.
- Wahlweise stehen die Abweichungen in der Statusleiste (`R− Q− HINTS OFF`).
- Befehl `Atlas.CompilerSwitches`

Einstellungen: `build.compilerSwitches`, `build.showSwitchesInStatusBar`

### Bauen-Werkzeug für Claude Code

`build_project` baut offene Projekte über den Compiler der IDE, auch in der Starter-Edition.

## Testen

- **DUnitX-Tests** aus dem Editor ausführen und einen einzelnen Test im Debugger starten (Code Lens an `[Test]` und `[TestFixture]`)

### Veraltete Testergebnisse (#1770)

- Wurde ein Test seit seinem Lauf geändert, zeigt seine Marke der Code Lens den alten Stand grau und kursiv mit „(veraltet)“, z. B. „Test ausführen · bestanden (veraltet)“.
- Nur Leerraum oder Kommentare geändert: nicht veraltet. Wird die Änderung zurückgenommen, gilt das Ergebnis wieder.
- Die Klassenmarke ist veraltet, sobald einer ihrer Tests es ist; die Zählung „3/4 bestanden“ nimmt veraltete Ergebnisse nicht als bestanden.
- Auf Wunsch machen auch Änderungen in den Units, die die Testunit verwendet (und die zum Testprojekt gehören), das Ergebnis veraltet.
- „Veraltete Tests ausführen“ (*Atlas*-Menü, Befehlspalette) führt genau diese Tests aus.

Einstellungen: `tests.stale`, `tests.stale.units`

### Getestet von (#1778)

- Hinter dem Kopf jeder öffentlichen Methode einer normalen Unit steht, welche DUnitX-Tests sie prüfen, z. B. „3 Tests · bestanden“.
- Farben wie bei der Code Lens der Tests: grün erst, wenn jeder dieser Tests bestand, gelb bei Teilstand („3 Tests · 1/3 bestanden“), rot bei einem Fehlschlag. Wurde ein Test seit seinem Lauf geändert, steht der alte Stand grau und kursiv mit „(veraltet)“. Ohne Test steht grau „kein Test · Test anlegen“.
- Atlas sucht die Tests im Hintergrund rückwärts wie „Betroffene Tests ausführen“: mit Tiefe 1 nur Tests, die die Methode direkt aufrufen, mit größerer Tiefe auch über Zwischenstufen. Stößt die Suche an eine Grenze, steht „(unvollständig)“ dabei.
- Klick führt genau diese Tests aus; Strg+Klick listet sie, ein Eintrag springt zum Test. Ohne Test öffnet bzw. legt der Klick die Testunit an.
- Testunits selbst bekommen keine Marken; private und geschützte Methoden nur auf Wunsch. Ausblenden je Methode oder Datei über das Menü „Ausblenden“.

Einstellungen: `codeLens.coveredBy`, `tests.coveredBy.depth`, `tests.coveredBy.private`

### Ungetestete Methoden (#1783)

- An der unit-Zeile einer normalen Unit mit Testunit steht „7 von 12 Methoden getestet“: wie viele ihrer Methoden mindestens ein Test aufruft (Tiefe und private Methoden wie bei „getestet von“). Unter `tests.untested.warnPercent` Prozent (Vorgabe 50) ist die Marke gelb, sonst grau. Units ohne Testunit bekommen keine Marke.
- Klick zeigt ein Menü mit den ungetesteten Methoden; ein Eintrag springt zum Kopf der Methode, „Test anlegen“ öffnet bzw. legt die Testunit an.
- Gezählt werden Aufrufe aus Tests, das ersetzt keine Abdeckungsmessung; das Menü sagt es dazu.
- Befehl „Ungetestete Methoden des Projekts“ (Atlas-Menü und Befehlspalette, `Atlas.ListUntestedMethods`): für das Projekt der Unit im Editor je Unit eine Zeile in der Meldungsansicht, die mit den meisten ungetesteten Methoden zuerst, darunter je Methode eine Zeile, die per Doppelklick hinspringt. Units ohne Testunit stehen mit allen Methoden darin. Der Server begrenzt sich auf 60 s; was er nicht mehr erreicht, nennt eine Zeile am Ende.
- Ausblenden je Datei über das Menü „Ausblenden“.

Einstellungen: `codeLens.untested`, `tests.untested.warnPercent`

### Betroffene Tests beim Speichern (#1775)

- Nach dem Speichern einer Unit (auch Formular oder Include-Datei) ermittelt Atlas die Tests, die die Änderungen dieser Datei seit dem letzten Commit erreichen, und führt nur sie im Hintergrund aus. Gebaut wird wie mit „Vor den Tests bauen“.
- Kein Fenster springt auf: Das Atlas-Statusfeld zeigt „Tests: 3 betroffen · laufen …“, danach „Tests: 3/3 bestanden“ oder rot „Tests: 1 von 3 fehlgeschlagen“. Ein Klick auf die Zeile im Statusfenster zeigt die Ausgabe des Laufs in der Meldungsansicht.
- Code Lens und Atlas-Probleme folgen dem Lauf wie nach „Tests ausführen“.
- Speichern während eines Laufs bricht ihn nicht ab; danach folgt höchstens ein weiterer Lauf mit allen bis dahin gespeicherten Dateien.
- Kein Lauf während einer Debug-Sitzung, eines Builds oder eines anderen Testlaufs. Mehr betroffene Tests als `tests.onSave.max` oder alle Tests nötig: kein Lauf, nur ein Hinweis im Statusfeld.
- Gehört eine Testunit zu mehreren Testprojekten, nimmt der Lauf im Hintergrund die einmal bei „Tests ausführen“ getroffene Wahl.

Einstellungen: `tests.onSave` (Vorgabe aus, Schnellschalter), `tests.onSave.max`

### Fehlschlag an der Assert-Zeile (#1771)

- Ein fehlgeschlagener Test steht nicht mehr am Methodenkopf, sondern an der Anweisung, die fehlschlug: Wellenlinie über der Anweisung, dahinter grau „erwartet 4, erhalten 3“.
- Die Zeile kommt aus dem Stacktrace des Berichts (DUnitX mit JclDebug oder madExcept). Bricht der Test mit einer Ausnahme ab, ist es die auslösende Anweisung.
- Ohne Zeilen im Stacktrace sucht Atlas im Rumpf den einen Assert, dessen erwarteter Wert zum Bericht passt (`Assert.AreEqual(4, …)` bei „Expected 4 but got 3“); hat der Rumpf nur einen Assert, gilt dieser. Passen mehrere, bleibt es beim Methodenkopf.
- Eingefügte Zeilen nimmt der Eintrag mit wie jeder Befund; die Zeile in der Meldungsansicht springt zur Anweisung.
- Der kurze Text erscheint wie der Fehlertext am Zeilenende (`editor.inlineDiagnostics`).

Einstellungen: `tests.failureAtAssert`, `tests.failureInline`

### Erwartet und erhalten vergleichen (#1779)

Aufruf: *Atlas*-Menü, Befehlspalette, Kontextmenü einer Testunit (*Atlas › Tests*), außerdem der Knopf „Vergleichen“:

- im Hover über dem Fehlschlag (vor „Erklären“),
- an der Testmarke eines fehlgeschlagenen Tests (hinter „Debuggen“),
- auf der Kachel „Testergebnisse“ der Willkommensseite für den gewählten Fehlschlag des lokalen Laufs.

Den Knopf gibt es nur, wenn der Fehlschlag erwarteten und erhaltenen Wert hat.

- Zeigt den Fehlschlag des Tests am Cursor (bei einem `[TestCase]` den ersten fehlgeschlagenen Fall), sonst den zuletzt gemeldeten, in zwei Spalten: links erwartet, rechts erhalten.
- Abweichende Zeichen sind rot bzw. grün hinterlegt; Zeilen, die es nur auf einer Seite gibt, ganz, gegenüber eine graue Lücke.
- Zeilenenden (`↵`, `␍↵`, `␍`), Tabs (`→`) und Leerzeichen am Zeilenende (`·`) sind sichtbar; ein Unterschied nur darin fällt so auf.
- Sind beide Werte JSON bzw. XML, rückt Atlas sie vorher gleich ein; der Unterschied steht dann in seiner eigenen Zeile.
- Werte, die mit „...“ enden, tragen „(gekürzt)“ im Spaltenkopf.
- „Erhalten kopieren“ legt den erhaltenen Wert in die Zwischenablage, etwa um den erwarteten Wert im Test zu aktualisieren; Esc schließt.
- Nur für Fehlschläge, deren Bericht erwarteten und erhaltenen Wert nennt.

Einstellungen: `tests.compare`, `tests.compare.format`

### Testabdeckung im Editor (#275)

- „Testabdeckung laden …“ (*Atlas*-Menü, Befehlspalette) liest einen Bericht von [DelphiCodeCoverage](https://github.com/DelphiCodeCoverage/DelphiCodeCoverage) ein, ohne neu zu bauen: `CodeCoverage_Summary.xml` (mit `-xml -xmllines`) oder `jacoco.xml` neuerer Fassungen.
- In der Rinne steht dann an jeder Zeile mit Code ein schmaler Balken: grün durchlaufen, rot nicht durchlaufen. Der Tooltip nennt die Treffer, die Abdeckung der Datei und den Bericht.
- Wurde die Datei nach dem Bericht gespeichert, sagt der Tooltip, dass die Zeilen verschoben sein können.
- Ein neuer Lauf überschreibt den Bericht: Atlas liest ihn beim nächsten Wechsel bzw. nach einer Tipp-Pause neu. „Testabdeckung ausblenden“ vergisst ihn.
- Beispiel (Testprogramm mit Map-Datei, „Detailliert“; volle Pfade bei `-e` und `-m`, `-ife` vor `-u` bei Unitnamen mit Punkten):

  ```
  CodeCoverage.exe -ife -e C:\Projekt\Bin\Tests.exe -m C:\Projekt\Bin\Tests.map -u Rechner.Kern Rechner.Hilfen -sp C:\Projekt\Source -od C:\Projekt\Coverage -xml -xmllines -a ^-^-exit:Continue
  ```

Einstellung: `tests.coverage`

### Vergleichsdateien für Tests (#1881)
Für Exporte, Berichte, erzeugten Code oder JSON prüft ein Test das Ergebnis gegen eine gespeicherte Datei statt mit einem Assert je Zeile („Approval“). Die Hilfs-Unit `Atlas.Testing.Approval` liegt unter `Setup\Vorlagen` (MIT-Lizenz, nur RTL und DUnitX); ins Testprojekt kopieren oder ihren Ordner in den Suchpfad aufnehmen. Beispiel: [approval-tests.pas](../../Beispiele/approval-tests.pas).
- `TApproval.Verify(Ergebnis, 'TFixture.Methode')` vergleicht mit `TFixture.Methode.approved.txt`; eine eigene Endung (`'.json'`) und ein Normalisierer für Datum oder GUID sind möglich.
- Zeilenenden (CRLF, LF, CR) zählen nicht als Abweichung; Dateien sind UTF-8.
- Weicht das Ergebnis ab, liegt daneben `….received.txt` und der Test schlägt fehl mit „Approval: Abweichung ab Zeile 3, siehe …“; ohne approved-Datei mit „neu, bitte prüfen“.
- Übernehmen heißt: received in approved umbenennen und die approved-Datei einchecken; `.received.*` gehört in die Ignorierliste.
- Ordner: `tests.approvalFolder` der nächsten `atlas.json` über dem Testprogramm (Vorgabe `Tests\Erwartet`, relativ zu ihrem Ordner); ohne `atlas.json` neben der nächsten `.dproj`. `TApproval.Folder` setzt ihn im Code.
- Meldungen deutsch, mit `TApproval.English := True` englisch.
In der IDE (Modul Tests, `tests.approvalFiles`):
- Schlägt ein Test mit dieser Meldung fehl, zeigt seine Testmarke „Abweichung · Vergleich“, ohne approved-Datei „Neu · Vergleich“. Derselbe Knopf „Vergleichen“ steht im Hover des Fehlschlags und auf der Kachel *Testergebnisse*.
- Der Vergleich zeigt links die approved-, rechts die received-Datei (Zeilen einander zugeordnet wie bei erwartet und erhalten, #1779). *Als neue Erwartung übernehmen* ersetzt die approved-Datei durch die received-Datei und löscht diese; der nächste Lauf ist grün. *Zum Test* springt zum Methodenkopf.
- *Liegengebliebene .received-Dateien löschen* (Atlas-Menü, Befehlspalette) sucht im Ordner der Vergleichsdateien des zuletzt gelaufenen Testprojekts (ohne Lauf des aktiven Projekts), löscht nach Rückfrage alle `*.received.*` darin und bietet an, `*.received.*` in die nächste `.gitignore` einzutragen, wenn dort noch keine Zeile dafür steht.
- `tests.approvalFiles` aus: keine eigene Marke, kein Befehl; die Hilfs-Unit arbeitet weiter, ihre Fehlschläge erscheinen als gewöhnliche Fehlschläge.
Einstellungen: `tests.approvalFolder` (atlas.json), `tests.approvalFiles` (Plugin)
### Dauer der Tests und langsame Tests (#1772)

- Nach einem Lauf zeigt jede Marke der Testlinse die Dauer: „Test ausführen · bestanden · 12 ms“, ab einer Sekunde in Sekunden mit einer Nachkommastelle („1,2 s“). Die Klassenmarke zeigt die Summe ihrer Tests, eine `[TestCase]`-Methode die Summe ihrer Fälle.
- Liegt der langsamste Test einer Marke über `tests.slowMs` (Vorgabe 500 ms), folgt „· langsam“ und die Marke wird gelb, auch wenn er bestanden hat. Fehlgeschlagen bleibt rot, veraltet grau.
- Die Karte *Testergebnisse* der Willkommensseite listet unter den Fehlschlägen die fünf langsamsten Tests des letzten Laufs; Doppelklick öffnet den Test.
- *Langsamste Tests zeigen* (Atlas-Menü, Befehlspalette): alle Tests dieser Sitzung mit Dauer, der langsamste zuerst (höchstens 50); Doppelklick oder Eingabetaste springt zum Test.
- `tests.showDuration` aus: keine Dauer, keine Färbung, keine Liste auf der Willkommensseite, kein Befehl.

Einstellungen: `tests.showDuration`, `tests.slowMs`

<a id="window-atlastestsexplorer"></a>
### Fenster „Atlas-Tests“ (#1776)

Aufruf: *Ansicht › Atlas › Atlas-Tests*, Atlas-Menü oder Befehlspalette. Das Fenster lässt sich andocken und kommt mit dem Desktop wieder.

- Oben das Testprojekt (bei mehreren in der Projektgruppe zur Wahl, vorgewählt das aktive), darunter der Baum aller Tests: Testunit › Fixture › Test › Fall. Gelesen werden die Testunits des Testprojekts wie von der Testlinse, ohne Server; neu nach jedem Lauf, nach dem Speichern einer Testunit und mit *Neu einlesen*.
- Je Zeile ein Punkt mit dem Stand: grün bestanden, rot fehlgeschlagen, gelb nur zum Teil gelaufen, grau nicht gelaufen, grauer Ring bestanden, aber veraltet (#1770). Dahinter der Zähler „bestanden/alle“ (veraltete zählen nicht als bestanden) und die Dauer. Tests mit `[Ignore]` stehen mit „(ignoriert)“ da und zählen nicht.
- *Alle ausführen* baut das Testprojekt und startet alle Tests. *Ausgewählte ausführen* (Strg+R) startet genau die gewählten Zeilen (Mehrfachauswahl mit Strg und Umschalt, auch ganze Fixtures oder Testunits) mit `--run` und ihren Namen. *Ausgewählte debuggen* (Strg+D) startet sie im Debugger wie „Test debuggen“; der einmalige Haltepunkt am Anfang gilt nur bei einem einzelnen Test.
- Filter *Fehlgeschlagen*, *Nicht gelaufen*, *Veraltet* und *Langsam* (über `tests.slowMs`) wirken sofort, mehrere zusammen mit „oder“; das Suchfeld sucht im vollen Namen (Unit.Fixture.Methode.Fall). Der Weg zu jedem Treffer bleibt sichtbar.
- Doppelklick oder Enter springt zum Test, bei einem Fall zu seinem `[TestCase]`. Unten stehen zum gewählten Test Meldung, erwarteter und erhaltener Wert und der Stacktrace; Zeilen, die eine Unit des Testprojekts nennen, öffnen sich per Doppelklick.
- Die Ergebnisse gelten für diese Sitzung, je Testprojekt; Änderungen an einer Testunit zeigt das Fenster nach dem Speichern.
- `tests.window` aus: kein Menüeintrag, das Fenster wird nicht wiederhergestellt.

Einstellung: `tests.window`

### Testlisten im Fenster „Atlas-Tests“ (#2167)

Aufruf: Reiter oben im Fenster „Atlas-Tests“; „+“ legt eine Liste an.

- Neben „Alle“ steht je Liste ein Reiter. Im Reiter einer Liste zeigt der Baum nur ihre Tests; Filter und Suche gelten weiter. Die Kopfzeile nennt die Regeln, „12 von 340 Tests“ und die Ablage, daneben *Liste ausführen*.
- **Feste Listen** nennen Tests, Fixtures oder ganze Testunits: im Baum auswählen, Kontextmenü *Zu Liste hinzufügen ▸* (eine feste Liste oder *Neue Liste …*); im Reiter einer festen Liste entfernt *Aus „…“ entfernen* die Auswahl wieder.
- **Dynamische Listen** bestehen aus Regeln, die alle gelten müssen: *Kategorie ist / ist nicht* (an der Fixture oder am Test), *Unit/Fixture passt / passt nicht* auf ein Muster mit `*` und `?` (z. B. `*.Slow.*`), *Stand ist / ist nicht* fehlgeschlagen, nicht gelaufen oder veraltet. Neue Tests, die passen, gehören ohne Zutun dazu.
- Rechtsklick auf einen Reiter: *Umbenennen …*, *Regeln bearbeiten …* (dynamische Listen), *Duplizieren*, *Löschen*.
- Ablage je Liste: **im Projekt** steht sie in `atlas.json` neben der .dproj unter `testLists` und gilt für das Team (Reiter mit ◆); **nur für mich** steht sie in `%LOCALAPPDATA%\Atlas\test-lists.json`. Atlas ändert in `atlas.json` nur diesen Schlüssel; Kommentare und Reihenfolge bleiben.
- Ausführen: *Liste ausführen* im Reiter, in der Befehlspalette „Testliste ausführen: <Name>“, mit Strg+Alt+R (`tests.lists.runKey`) die zuletzt benutzte Liste. Kategorie-Regeln gehen als `--include`/`--exclude` an DUnitX, alle übrigen wertet Atlas aus und nennt die Tests über `--run`, zusammengefasst zu Fixtures und Namensräumen, wo es geht. Passt die Liste nicht in eine Befehlszeile, sagt es die Meldungsansicht.
- `tests.lists` aus: keine Reiter, kein Kontextmenü, kein Befehl; `testLists` in `atlas.json` wird nicht gelesen.

```json
"testLists": [
  {"name": "Vor dem Commit", "rules": [{"category": "Benchmark", "exclude": true}, {"unit": "*.Slow.*", "exclude": true}]},
  {"name": "Parser", "tests": ["Atlas.Common.Pascal.Tests"]}
]
```

Einstellungen: `tests.lists`, `tests.lists.runKey`

### Wackelnde Tests (#1773)

Ein Test wackelt, wenn er ohne Änderung an seinem Rumpf mal grün und mal rot ist (Zeit, Threads, Reihenfolge, Dateien).

- Atlas merkt sich nach jedem Lauf aus der IDE je Test die letzten Ergebnisse (`tests.flaky.runs`, Vorgabe 10) mit der Prüfsumme des Methodenrumpfs wie bei „veraltet“ (#1770). Ein Test mit `[TestCase]` gilt in einem Lauf als rot, wenn einer seiner Fälle rot war; nur übersprungen zählt nicht.
- „Wackelt“: Unter den Ergebnissen mit dem Rumpf von jetzt gibt es grün, danach rot, danach wieder grün. Rot, dann am Rumpf repariert und grün, wackelt nicht.
- Die Marke der Testlinse wird gelb: „Test ausführen · bestanden · wackelt (3 von 10 rot)“; die Klassenmarke nennt die Zahl ihrer wackelnden Tests („· 2 wackeln“).
- Im Fenster *Atlas-Tests* steht hinter dem Test „· wackelt“, der Filter *wackelt* zeigt nur diese Tests. Die Einzelheiten zeigen den Verlauf als Reihe (✓ grün, ✗ rot, ältester zuerst) mit „2 von 10 rot“, seit wann der Rumpf unverändert ist und die letzte Fehlermeldung.
- *Wackelnde Tests zeigen* (Atlas-Menü, Befehlspalette) öffnet das Fenster mit genau diesem Filter.
- Ist ein Test, der beim Lauf davor rot war, jetzt grün, wackelt aber (etwa nach *Fehlgeschlagene Tests erneut ausführen*), meldet die Meldungsansicht „Test TRechnerTests.Summe bestanden, wackelt aber (3 von 10 Läufen rot).“
- Der Verlauf liegt je Testprojekt in `%LOCALAPPDATA%\Atlas\projects\tests-history\<Schlüssel>.json` (Schlüssel wie die Projekt-Zusammenfassung) und übersteht einen Neustart der IDE.
- `tests.flaky` aus: Atlas schreibt keinen Verlauf, keine Marke, kein Befehl.

Einstellungen: `tests.flaky`, `tests.flaky.runs`

### Teststand in der Statusleiste (#1777)
- In der Atlas-Statusleiste steht hinter dem Status „Tests 41/42“ (bestanden/gelaufen, übersprungene zählen nicht) mit Ampelpunkt für das Testprojekt der aktuellen Datei: in einer Testunit ihr Testprojekt, sonst das aktive Testprojekt bzw. das erste der Projektgruppe. Während eines Laufs „Tests laufen …“, vor dem ersten Lauf der Sitzung „Tests –“. Ohne Testprojekt kein Feld.
- Ampel: rot bei Fehlschlägen, gelb während eines Laufs und bei veralteten Ergebnissen (wenn das Fenster „Atlas-Tests“ dieses Testprojekt zeigt), grün, wenn alles bestand.
- Klick: fehlgeschlagene Tests erneut ausführen; sind alle grün, alle. Rechtsklick: *Alle ausführen*, *Fehlgeschlagene erneut ausführen*, *Betroffene ausführen*, *Fenster „Atlas-Tests“*, *Ergebnisse auf der Willkommensseite*.
- Tooltip: Testprojekt, Uhrzeit und Dauer des letzten Laufs, bestanden, fehlgeschlagen, übersprungen und veraltet.
- Ohne das Element *Status* in der Leiste steht das Feld als Text in der Statuszeile der IDE (ohne Punkt und Rechtsklick).
Einstellung: `editor.statusBar.tests`
### Protokoll je Test (#2168)
Was ein Test unterwegs ausgibt (`Log`/`Status` von DUnitX, `WriteLn` in der Testklasse, `WriteLn` der getesteten Klassen), zeigt das Fenster „Atlas-Tests“ im Reiter *Protokoll (n)* neben *Einzelheiten*, genau für den gewählten Test.
- Der XML-Bericht von DUnitX enthält keine Log-Zeilen. Deshalb gibt es die Hilfs-Unit `Atlas.Testing.Log` unter `Setup\Vorlagen` (MIT-Lizenz, nur RTL und DUnitX): ins Testprojekt aufnehmen und nach `TDUnitX.CreateRunner` die Zeile `runner.AddLogger(TAtlasTestLogger.Create);` einfügen. Der Logger arbeitet nur in Läufen aus Atlas: Atlas legt vor dem Start eine leere Seitendatei neben den Bericht, nur dann schreibt er hinein und setzt Marken um jeden Test in die Konsolenausgabe.
- Je Zeile die Zeit ab Teststart (`01,190`), dann der Text; Warnungen und Fehler mit „Warnung:“ bzw. „Fehler:“, Konsolenzeilen mit „Konsole:“ (ohne Zeit, an der Stelle zwischen den Log-Meldungen, an der sie kamen). Start und Ende des Tests stehen dabei.
- Setup und TearDown der Fixture gehören zu keinem Test: Ihre Zeilen stehen an der Fixture. Zeilen zwischen zwei Tests (etwa aus einem Thread, der den Test überdauert) stehen beim vorigen Test mit „(nach Testende)“. Ein Test mit `[TestCase]` zeigt die Zeilen aller Fälle mit dem Namen des Falls davor.
- Verweise wie `Kunden.pas:42`, `Kunden.pas(42)`, Zeilen eines Stacktraces und `Unit.Klasse.Methode` öffnen per Doppelklick bzw. Enter die Stelle, wenn die Unit zum Testprojekt gehört.
- Auch bei grünen Tests abrufbar; *Kopieren* bzw. Strg+C legt das ganze Protokoll in die Zwischenablage.
- Ohne eingetragenen Logger zeigt der Reiter, wie man ihn einschaltet, und darunter die Ausgabe des ganzen Laufs.
- Je Test höchstens `tests.log.maxLines` Zeilen (Vorgabe 2000), der Rest wird mit Hinweis abgeschnitten. `tests.log` aus: kein Reiter, keine Seitendatei.
Einstellungen: `tests.log`, `tests.log.maxLines`
### Lecks je Test (#1774)

- Mit Leckmonitor im Testprojekt (`DUnitX.MemoryLeakMonitor.FastMM4` bzw. `FastMM5`) meldet DUnitX einen Test, der Speicher nicht freigibt, als Fehlschlag („40 bytes were leaked in the test method“). Atlas zeigt ihn als bestanden mit Leck: Die Marke wird gelb, „Test ausführen · bestanden · Leck: 40 Bytes“.
- In *Atlas-Probleme* steht am Methodenkopf eine Warnung „Test TKontoTests.Bucht gibt Speicher nicht frei: 40 Bytes (Leck)“, Quelle DUnitX.
- Die Meldungsansicht nennt nach dem Lauf, wie viele Tests mit Leck bestanden und wie viele Bytes zusammen nicht freigegeben wurden.
- Ein Leck in Setup oder TearDown zählt beim Test, in dem es auftrat.
- Lecks am Programmende, die keinem Test gehören (Objekte, die das Testprogramm erst beim Beenden als nicht freigegeben meldet), nennt die Meldungsansicht in einer Zeile: „Tests: Lecks am Programmende, keinem Test zuzuordnen: 3 Blöcke (TStringList x 2, TKonto x 1).“ Gelesen wird der Bericht von FastMM (`<Programm>_MemoryManager_EventLog.txt` neben der EXE, wenn der Lauf ihn geschrieben hat), sonst die Ausgabe des Programms.
- Fehlt dem Testprogramm der Leckmonitor, meldet die Regel `dunitx-leak-monitor` einen Hinweis am Eintrag `DUnitX.TestFramework` der .dpr. Die Korrektur trägt `DUnitX.MemoryLeakMonitor.FastMM4` ein (er arbeitet auch mit dem Speichermanager der RTL, ohne `FastMM4.pas`), bei FastMM5 `DUnitX.MemoryLeakMonitor.FastMM5`. Den Speichermanager selbst richtet „Leckprüfung einrichten …“ ein.
- `tests.leaks` aus: Das Ergebnis bleibt, wie DUnitX es meldet (Fehlschlag, rot), die Zeile zu Lecks am Programmende entfällt.

Einstellung: `tests.leaks`

### Testfall aus der Unit anlegen (#1226)

Aufruf: Code-Aktion (Alt+Enter) an einer Methode oder Routine, im Rumpf oder an der Deklaration; im Rumpf auch `/test`.

- Atlas findet die Testunit (Muster `testUnits.pattern`) und trägt einen Entwurf der Testmethode in die Testklasse ein, die getestete Unit kommt ins uses.
- Der Entwurf bereitet je Parameter eine Variable mit Platzhalter vor (`0`, `''`, `False`, `nil`, `Default(T)`), ruft die Methode über das Objekt der Testklasse (ein Feld vom Typ der Klasse), über die Klasse (Klassenmethoden) oder über ein lokales Objekt mit `try … finally` auf und prüft Ergebnis und `var`/`out`-Parameter mit Platzhaltern passend zum Typ (`Assert.AreEqual`, mit Toleranz bei Gleitkomma, `Assert.IsTrue`, `Assert.IsNotNull`).
- Ein `Assert.Fail` am Ende hält den Entwurf rot, bis die erwarteten Werte stimmen.
- Fehlt die Testunit, legt Atlas sie wie *DUnitX-Testunit anlegen* an (Fixture, Setup/TearDown, Eintrag in `.dpr` und `.dproj`) und setzt den Entwurf an die Stelle des leeren Tests.
- Private, geschützte und nur im implementation-Teil deklarierte Routinen sind von der Testunit aus nicht aufrufbar; für sie entsteht nur der Test mit `Assert.Fail`.

### Test aus dem Debug-Halt anlegen (#1873)

Aufruf: Knopf *Test daraus anlegen …* in der Exception-Leiste, Kontextmenü des Editors › Atlas › Tests beim Debuggen oder Befehlspalette (*Test aus dem Debug-Halt anlegen …*). Einstellungen unter Debuggen: `tests.fromDebugStop` (Vorgabe an), `tests.fromDebugStop.fields` (an), `tests.fromDebugStop.properties` (aus), `tests.fromDebugStop.maxArray` (20).

- Atlas nimmt den Rahmen des Halts: bei einer Exception in RTL oder VCL den ersten Rahmen in eigenem Code, sonst den obersten mit Quelltext.
- Steht der Rahmen oben, wertet der Debugger die Parameter und die Felder der Klasse aus (`Self.FEinheit`), ohne Nebenwirkungen; Getter nur mit `tests.fromDebugStop.properties`. In einem tieferen Rahmen kommen die Parameter aus der Kopfzeile des Aufrufstacks.
- Aus den Texten des Debuggers werden Delphi-Literale: Zahlen (Dezimalkomma wird Punkt), Strings mit `''` und `#nn`, Boolean, Aufzählungswerte, Mengen und dynamische Arrays bis `tests.fromDebugStop.maxArray` Elemente. Objekte, Zeiger, Interfaces, Records und alles Unklare rät Atlas nicht: Der Test bekommt dort ein TODO.
- Der Dialog zeigt die Werte zum Abwählen (abgewählte bleiben Platzhalter; private Felder und Objekte sind abgewählt), die Art (*Soll funktionieren* bzw. *Soll EConvertError werfen*, wenn das Programm an einer Exception steht), bei Funktionen das erwartete Ergebnis und den Namen (`ParseMit12_5Kg`, `ParseMit12_5KgWirftConvertError`).
- *Test anlegen* trägt den Test wie *Testfall aus der Unit anlegen* in die Testunit ein (legt sie bei Bedarf samt `.dpr`/`.dproj` an), mit einer Kommentarzeile „Aus Debug-Halt 2026-11-13 10:42, EConvertError“; eine Exception prüft `Assert.WillRaise`. Ohne erwartetes Ergebnis bleibt der Test mit `Assert.Fail` rot. Alles ist ein Rückgängig-Schritt, danach springt Atlas zum Test.
- Ohne das Modul Debugger fehlen Knopf und Befehl.

### Schnellbefehle für Tests und Fehlersuche (#305)

Aufruf: Befehl in eine leere Zeile schreiben und Enter drücken.

- `/mock IKundenRepo` auf Unit-Ebene legt `TKundenRepoMock = class(TInterfacedObject, IKundenRepo)` mit allen Methoden des Interfaces an (auch geerbten): Jede Methode zählt ihre Aufrufe (`LadenCalls`), Funktionen liefern ein einstellbares Feld (`LadenResult`). In einer Routine einer Unit, die `Delphi.Mocks` verwendet, entsteht stattdessen eine lokale Variable `TMock<IKundenRepo>` samt `Create`.
- `/testcase 'a', 2, True` über einer Testmethode schreibt `[TestCase('Fall1', 'a,2,True')]`, fortlaufend nummeriert; enthält ein Wert ein Komma, trennt `;`. Die Zahl der Werte muss zu den Parametern der Methode darunter passen.
- `/dump` in einer Routine gibt alle Parameter und lokalen Variablen einfacher Typen in einer Zeile aus (`OutputDebugString` bzw. die Routine aus `slashCommands.logCall`).
- `/assert` unter einer Zuweisung prüft die zugewiesene Variable passend zum Typ (`Assigned`, nicht leer, nicht negativ, `True`); in Testunits mit `Assert.IsNotNull`, `Assert.AreNotEqual` und `Assert.IsTrue` aus DUnitX.

### Betroffene Tests ausführen (#1353)

Aufruf: *Atlas*-Menü, Befehlspalette.

- Atlas vergleicht die Arbeitskopie mit der Basis (Git: Merge-Base mit `main`, SVN: `BASE`, nicht eingecheckte Änderungen zählen mit).
- Es bestimmt die geänderten Routinen, Typen und Konstanten:
  - Änderungen im interface zählen für das Symbol
  - uses und initialization für die ganze Unit
  - `.dfm` für die Formularklasse
  - `.inc` für die einbindenden Units
  - Kommentare nicht
- Es verfolgt ihre Auswirkungen bis zur Tiefe und führt nur die DUnitX-Tests aus, die sie erreichen; jeder mit Grund in der Meldungsansicht.
- Sind mehr als 80 % einer Fixture betroffen, läuft die ganze.
- Auf Wunsch bietet ein Git-Hook die Tests vor jedem Commit an.
- Dieselbe Auswahl gibt es auf der Kommandozeile (`--affected-tests`) und für Claude Code (`get_affected_tests`).

Einstellungen: `tests.affected`, `tests.affectedDepth`, `tests.affectedBeforeCommit`

## Debuggen

### Starten und Schritte

- **Startprofile** für Parameter, Arbeitsordner, Umgebung und Host-Anwendung

#### Gezielt hineinspringen (Strg+Alt+F7)

- Bei `Speichere(Kunde.Name, Format(…))` zeigt Atlas im angehaltenen Programm die Aufrufe der Zeile in Ausführungsreihenfolge (`1 TKunde.GetName (Getter)`, `2 Format`, `3 Speichere`).
- Es springt mit Ziffer oder Enter direkt in den gewählten, ohne durch die anderen zu gehen.
- virtuelle Aufrufe nach dem Laufzeittyp
- ohne Quelltext oder Debug-DCUs ausgegraut
- ein einziger Aufruf wie F7

Einstellungen: `debug.stepIntoTarget`

#### Beim nächsten Ereignis anhalten

Aufruf: Menü Start und Befehlspalette. „Welcher Code läuft, wenn ich hier klicke?“

- Ereignisarten wählen (Maus, Tastatur, Timer, Fenster, Datenbank, Aktionen, Sonstige), auf Wunsch ein Formular oder nur die sichtbaren.
- Atlas setzt vorübergehende Haltepunkte auf alle passenden Handler aus den Formularen und aus Zuweisungen im Code (`Btn.OnClick := …`).
- Es hält im nächsten, der läuft, entfernt alle wieder und zeigt `Angehalten: btnOk.OnClick → TfrmKunde.btnSpeichernClick` (geteilte Handler über `Sender.Name`).
- „Weiter beobachten“ setzt sie erneut.
- Häufige Ereignisse (`OnPaint`, `OnMouseMove`, `OnUpdate`, Timer unter 100 ms) nur auf ausdrückliche Wahl (`debug.breakOnNextEvent.excluded`).

Einstellungen: `debug.breakOnNextEvent`

<a id="window-atlasstepfilter"></a>
#### Schrittfilter

- F7 hält nicht mehr:
  - in Gettern und Settern mit einer Anweisung
  - in trivialen Routinen (eine Zuweisung an Result oder ein Feld)
  - in Klassen-Operatoren und Konstruktoren, die nur `inherited` aufrufen
- F7 überspringt jede Routine, auf die ein Muster wie `*.Log*` oder `TBasisForm.*` passt.
- Rechtsklick auf eine Methode, „Beim Hineinspringen überspringen“ nimmt sie auf.
- Ein Haltepunkt in einer übersprungenen Routine hält trotzdem.
- Umschalt+F7 springt einmal ohne Filter hinein.
- Das andockbare Fenster „Schrittfilter“ zeigt, auf wie viele Routinen des Projekts jede Art und jedes Muster passt.

Einstellungen: `debug.stepFilters`

<a id="window-atlasmemorytimeline"></a>
#### Speicherverlauf

Aufruf: Atlas-Menü › Speicherverlauf bzw. Befehl `Atlas.DebugMemory`.

- Das Fenster „Atlas: Speicher“ zeigt während einer Debug-Sitzung privaten Speicher, Arbeitssatz, Handles, GDI- und USER-Objekte des Programms als Linie über die Zeit.
- Gemessen wird von außen im Takt (Vorgabe 1 s), das Programm hält dafür nicht an.
- Jeder Halt setzt eine Marke, eine Exception eine rote; „Marke setzen“ setzt eine eigene.
- Mit der Maus einen Bereich ziehen: Darunter steht der Zuwachs aller Werte, etwa `Privater Speicher +38,0 MB · Handles +12`. Doppelklick hebt die Wahl auf.
- „CSV kopieren“ legt den Verlauf samt Marken in die Zwischenablage, „Leeren“ beginnt neu.
- Grenze: In der 32-Bit-IDE kappt Windows Speicherwerte eines 64-Bit-Programms über 4 GB.

Einstellungen: `debug.memoryTimeline`, `debug.memoryTimeline.intervalMs`

<a id="window-atlasbreakpoints"></a>
#### Haltepunktfenster

Das andockbare Fenster „Haltepunkte“ (Atlas-Menü, „Haltepunkte (Atlas)“) zeigt dieselben Haltepunkte wie die Liste der IDE, dazu:

- Suche über Dateiname, Methode, Bedingung und Etikett; mehrere Wörter müssen alle passen
- Filterchips „aktiv“, „mit Bedingung“, „nie getroffen“ (in dieser Sitzung) und „greift nicht“
- Trefferzahl dieser Debug-Sitzung; „Zähler zurücksetzen“ setzt sie auf 0
- Etiketten wie `Import` oder `Bug 4711`, mehrere je Haltepunkt, mit Vervollständigung der schon benutzten; sie sind persönlich und bleiben nach einem Neustart erhalten
- Gruppieren nach Etikett, Datei oder Gruppe, Gruppen auf- und zuklappbar
- mehrere Haltepunkte gemeinsam ein- und ausschalten, mit Etikett versehen oder löschen (Rückgängig mit Strg+Z)
- Spalten „Satz“ (Haltepunkt-Sätze) und „Regeln“ (Trefferbedingung, Thread-Filter, abhängig von einem anderen Haltepunkt), etwa „ab 3. Treffer · Hauptthread“
- Doppelklick springt zur Stelle, Enter öffnet die Eigenschaften der IDE
- Spalten über das Kontextmenü ein- und ausblenden, Breite und Reihenfolge merkt sich das Fenster

Einstellungen: `debug.breakpointsWindow`

#### Haltepunkte, die nicht greifen werden

Vor jedem Start einer Debug-Sitzung prüft Atlas alle aktiven Quelltext-Haltepunkte, offene Dateien mit dem Stand im Editor:

- Zeile ohne Code (Kommentar, Leerzeile, Deklaration) mit der nächsten Codezeile derselben Routine
- inaktiver Zweig der bedingten Kompilierung mit seiner Bedingung (`{$IFDEF RELEASE}`)
- Code ohne Debug-Informationen (`{$D-}` in der Unit oder in den Projektoptionen)
- Unit eines anderen Projekts der Gruppe, nicht des gestarteten

Gibt es Funde, zeigt der Dialog „Haltepunkte, die nicht greifen werden“ sie vor dem Start; Doppelklick springt zur Stelle. „Auf nächste Codezeile verschieben“ verschiebt die Haltepunkte samt Bedingung, Durchlaufzahl und Gruppe und startet, „Trotzdem starten“ startet unverändert, „Abbrechen“ startet nicht. Der Befehl „Haltepunkte prüfen“ (Menü Atlas, Befehlspalette) prüft jederzeit. Ohne Server oder ohne Antwort in 3 Sekunden startet die IDE ohne Meldung.

Einstellungen: `debug.checkBreakpoints`

#### Haltepunkte auf Methoden nach Muster

Der Befehl „Haltepunkt auf Methoden …“ (Menü Atlas, Befehlspalette, Kontextmenü des Editors unter „Debuggen“ und Kontextmenü der Haltepunktliste) setzt Haltepunkte auf alle Methoden, die zu einem Namen oder Muster passen, ohne jede einzeln zu öffnen. Das Startmuster kommt aus dem Wort am Cursor: im Kopf einer Methode `TKunde.Speichere`, auf einem Typ `TKunde.*`, auf einem Aufruf `FKunde.Speichere` der Name `Speichere`; eine einzeilige Markierung wird übernommen. Ohne Wort steht das zuletzt benutzte Muster da.

- `TKunde.Speichere`, `TKunde.*` (alle Methoden der Klasse), `*.Validiere*` (alle passenden Methoden und Routinen), `Kunde.Import.*` (ganze Unit), `IAuftrag.Pruefe` (alle Klassen, die den Interface-Member umsetzen, auch über Methodenzuordnungen)
- mit Parametertypen nur eine Überladung: `TKunde.Speichere(Integer)`
- „Überschreibungen“ nimmt die override-Methoden der Nachfahren dazu, „Überladungen“ alle Überladungen eines Namens (beide Vorgabe an)

Die Vorschau zeigt die Treffer mit Datei und Zeile zum Abwählen, Methoden ohne Quelltext grau. „Setzen“ legt die Haltepunkte am ersten ausführbaren Befehl jeder Methode an, in der Haltepunktgruppe mit dem Muster als Namen, auf Wunsch mit Bedingung oder „Nicht anhalten, nur protokollieren“. Mit „Mitwachsen“ ergänzt Atlas beim nächsten Debug-Start Haltepunkte für neue passende Methoden und nennt sie in den Meldungen. „Haltepunktgruppen der Methoden …“ schaltet die Gruppen des Projekts ein und aus oder entfernt sie samt Haltepunkten. Die Gruppen merkt sich Atlas persönlich je Projekt.

Einstellungen: `debug.methodBreakpoints`

#### Bis hier ausführen per Klick

Aufruf: Rand des Editors im angehaltenen Zustand, Kontextmenü Atlas › Debuggen, Befehlspalette. Statt den Cursor zu setzen und F4 zu drücken, genügt ein Klick neben die Zeile.

- Hält das Programm an, erscheint rechts der Zeilennummern eine schmale Spalte; an ausführbaren Zeilen zeigt sie unter dem Mauszeiger ▶ mit einem Tooltip.
- Klick auf ▶ führt bis zu dieser Zeile aus (wie F4); Strg+Klick dabei ohne Halt an anderen Haltepunkten.
- Übersprungene Haltepunkte sind nach dem nächsten Halt wieder im alten Zustand, auch wenn das Programm vorher endet. Stürzt die IDE dazwischen ab, setzt Atlas sie beim nächsten Start einer Debug-Sitzung zurück.
- Rechtsklick in den Rand: „Bis hier ausführen“, „Bis hier, Haltepunkte überspringen“ (auch Strg+F4, nur im angehaltenen Zustand) und „Einmaliger Haltepunkt“. Der einmalige Haltepunkt steht in der Gruppe `Atlas.Einmalig` und verschwindet nach dem ersten Halt; setzen lässt er sich auch ohne laufendes Programm.
- Ausführbar sind Zeilen zwischen `begin` und `end` eines Rumpfs, ohne Leer- und Kommentarzeilen und ohne Zeilen, die nur `begin`, `end`, `try`, `finally`, `except` oder `else` enthalten.

Einstellungen: `debug.runToClick`

#### Haltepunkt nur für ein Objekt

Ein Haltepunkt in `TKunde.Speichere` hält bei 500 Kunden 500 Mal. Im angehaltenen Programm, mit der Schreibmarke auf der Zeile des Haltepunkts, bietet das Kontextmenü des Editors unter Debuggen:

- „Haltepunkt nur für dieses Objekt“: Atlas wertet `Pointer(Self)` aus und schreibt `Pointer(Self) = Pointer($0A3F1C20)` in die Bedingung. Die Adresse gilt nur in dieser Sitzung.
- „Haltepunkt nur wenn …“: Auswahl aus den Feldern von `Self` mit einfachem Wert, etwa `FNr = 4711`; die Bedingung gilt auch in späteren Sitzungen.

Eine vorhandene Bedingung bleibt erhalten und wird mit `and` verknüpft. Beides gibt es nur in Methoden, nicht in freien Routinen und Klassenmethoden. Vor dem nächsten Start fragt Atlas nach Adressbedingungen der letzten Sitzung: entfernen, durch eine Feldbedingung ersetzen oder behalten.

Einstellungen: `debug.instanceBreakpoints`
#### Haltepunkt-Sätze

Aufruf: Menü Atlas und Befehlspalette. Wer an mehreren Fehlern arbeitet, wechselt zwischen benannten Sätzen von Haltepunkten, statt sie zu löschen und neu zu setzen.

- „Haltepunkte als Satz speichern …“ nimmt alle Quelltext-Haltepunkte mit Bedingung, Durchlaufzahl, Gruppe, Aktionen und an/aus auf; auf Wunsch an den aktuellen Branch gekoppelt.
- „Haltepunkt-Satz wechseln …“ legt fehlende Haltepunkte des Satzes an und schaltet die Haltepunkte anderer Sätze aus (gelöscht wird nichts). Haltepunkte, die zu keinem Satz gehören, bleiben, wie sie sind.
- „Haltepunkt-Satz hinzufügen …“ ergänzt die Haltepunkte eines Satzes, ohne andere auszuschalten; „Haltepunkt-Satz löschen …“ entfernt nur den Satz.
- Atlas findet die Zeile beim Laden über Methode und Zeilentext wieder, auch wenn darüber Zeilen eingefügt wurden; nicht mehr auffindbare Haltepunkte nennt eine Zeile in den Meldungen.
- Sätze liegen je Projekt in `.atlas/breakpoints/<Name>.json` und lassen sich im Repository teilen.
- Mit `debug.breakpointSetPerBranch` wird ein gekoppelter Satz aktiv, sobald die Arbeitskopie auf seinen Branch wechselt (Git und SVN).
- Die Haltepunktgruppen der IDE bleiben unberührt: Sie schalten Haltepunkte über Aktionen, hängen aber an Zeilennummern in der `.dsk`; ein Satz merkt sich die Gruppe jedes Haltepunkts mit.

Einstellungen: `debug.breakpointSetPerBranch`

#### Haltepunkte wandern mit dem Code

Läuft von selbst; Befehle im Menü Atlas und in der Befehlspalette. Nach `git pull`, Branchwechsel oder Formatierer stehen Haltepunkte der IDE sonst auf falschen Zeilen, weil sie an Zeilennummern hängen.

- Atlas merkt sich zu jedem Quelltext-Haltepunkt einen Anker: Routine, Abstand zum Routinenanfang, Zeilentext und Nachbarzeilen (dieselbe Suche wie bei den Haltepunkt-Sätzen).
- Ändert sich eine Datei von außen (neu geladen, Branchwechsel, beim letzten Schließen der IDE anders, oder fünf und mehr Zeilen auf einmal wie bei Formatierer und Code-Aktionen), setzt Atlas jeden Haltepunkt auf die passende Zeile, mit Bedingung, Durchlaufzähler, Gruppe, Aktionen und an/aus. Beim normalen Tippen nimmt die IDE ihre Haltepunkte selbst mit; Atlas merkt sich nur den neuen Anker.
- Eine Zeile in den Meldungen nennt jede Verschiebung und „3 verschoben, 1 verwaist“.
- Nicht eindeutig zuzuordnende Haltepunkte bleiben stehen und kommen in die Liste „Verwaiste Haltepunkte …“ mit Vorschlag (gleicher Abstand in der Routine) und den Knöpfen „Vorschlag übernehmen“ und „Löschen“. Gelöscht wird nichts von selbst.
- „Haltepunkte zurück an alte Zeilen“ nimmt das letzte Nachziehen zurück.
- Die Anker liegen in `%LOCALAPPDATA%\Atlas\breakpoint-anchors.json`.

Einstellungen: `debug.breakpointAnchors`

#### Haltepunkt-Regeln: abhängig, Treffer, Thread

Aufruf: Kontextmenü des Editors (Atlas › Debuggen › „Haltepunkt-Regeln …“, auch im Rand), Menü Atlas, Befehlspalette; auf der Zeile eines Haltepunkts. Ein Haltepunkt in einer viel benutzten Routine hält sonst hundertmal, bevor man an der Stelle ist, um die es geht.

- „Erst aktiv nach“: Der Haltepunkt ist zu Beginn jeder Debug-Sitzung aus und wird eingeschaltet, sobald der gewählte andere Haltepunkt gehalten hat. „bis zum Ende der Sitzung“ lässt ihn danach an, „nur einmal“ schaltet ihn nach seinem Halt wieder aus, bis der auslösende erneut hält. Nach der Sitzung ist er wieder an.
- „Anhalten“: bei jedem, genau beim n-ten, ab dem n-ten oder bei jedem n-ten Treffer; gezählt wird je Sitzung.
- „Thread“: alle, Name enthält (aus `TThread.NameThreadForDebugging`), eine Thread-ID oder nur der Hauptthread. Ein Halt in einem anderen Thread zählt nicht als Treffer.
- Bedingung der IDE, Trefferbedingung und Thread-Filter gelten zusammen. Für Treffer und Thread hält der Debugger kurz an, Atlas zählt und setzt sofort fort; in heißen Schleifen kostet das Zeit.
- Fehlt der auslösende Haltepunkt beim Start, bleibt der abhängige normal an, und eine Zeile in den Meldungen sagt es.
- Regeln liegen in `%LOCALAPPDATA%\Atlas\breakpoint-rules.json` und ziehen mit, wenn „Haltepunkte wandern mit dem Code“ einen Haltepunkt verschiebt.

Einstellungen: `debug.breakpointRules`

### Werte ansehen

- **Werte im Hover beim Debuggen** (siehe [Verstehen](Verstehen.md))

#### Visualisierer für häufige Typen

- einzeilige Zusammenfassung statt roher Objektdarstellung im Hover, in Überwachten Ausdrücken und Lokalen Variablen, etwa:
  - `TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]`
  - `TFDQuery · dsEdit · 3/10 · Name = Meier, Ort = Berlin`
  - `clWebDodgerBlue · $1E90FF`
- Die Lupe öffnet ein Ansichtsfenster mit Tabelle, Hex-Ansicht, JSON-Baum, Bild oder Farbfeld.
- Listen, Dictionaries, Datenmengen, Bytes und Streams, JSON, Farben, TGUID, TPoint/TRect/TSize und Bitmaps, je Art abschaltbar
- Auswertung mit Zeitlimit und ohne Nebenwirkungen, soweit nicht erlaubt (`debug.visualizers.evaluation`)

Einstellungen: `debug.visualizers`

#### Eigene Wertdarstellung je Typ

- `// atlas-debug: '{Name}, {Ort} (Nr {Nr})'` oder `[AtlasDebugDisplay('…')]` (mitgelieferte Unit `Atlas.Debug.Attributes`) über der Klasse, und `TKunde` erscheint im Hover, in Überwachten Ausdrücken und Lokalen Variablen als `Meier, Berlin (Nr 4711)`.
- Nachfahren erben die Regel.
- Fremde Klassen wie `TFDConnection` bekommen sie über `debugDisplayRules` in der Projektdatei `.atlas`.
- Platzhalter:
  - mit Format (`{Betrag:0.00}`)
  - `{?Feld}` statt des ganzen Werts, wenn etwas nicht auswertbar ist
  - Getter und Aufrufe nur mit `debug.displayRules.allowCalls`
- `// atlas-debug-children: Name, Ort` beschränkt die Unterelemente im Ansichtsfenster („Alle Felder“ bleibt).
- Im Editor vervollständigt Atlas die Platzhalter, die Regel `debug-display-placeholder` markiert unbekannte.

Einstellungen: `debug.displayRules`

#### Werte im Editor beim Debuggen

- Solange der Prozess steht, stehen die Werte der lokalen Variablen, Parameter, Schleifenvariablen und Felder von `Self` gedimmt am Ende der Zeilen der aktuellen Routine (`Count = 3, Name = 'Meier'`).
- Seit dem letzten Schritt geänderte Werte sind hervorgehoben, `TDateTime` erscheint als Datum.
- Ausgewertet werden nur schlichte Namen, nie Aufrufe oder Eigenschaften, in kleinen Zeitscheiben, damit F8 schnell bleibt.

Einstellungen: `debug.inlineValues`, `debug.inlineValuesPerLine`

#### „Warum bin ich hier?“

- Beim Halt stehen am Ende der Kopfzeilen der umgebenden `if`, `while`, `repeat … until`, `for` und `case` die Werte ihrer Bedingungen, gedimmt wie die Werte im Editor: `(1200 > 1000) and True → True`, `I = 3 von 7`, `Art = paRabatt → paRabatt`, im `else`-Zweig `(4 = 0) → False, else-Zweig`.
- Kurzschluss wie im Programm: Entscheidet bei `A and B` schon `A = False`, steht bei B „nicht nötig“.
- Aufrufe und Getter wertet Atlas nicht von selbst aus (`‹Aufruf›`); ein Klick auf den Text der Zeile fragt nach und führt sie dann aus.
- Nur in Dateien mit Quelltext, bis zur Routine, höchstens `debug.whyHere.depth` Blöcke (Vorgabe 3); die Werte verschwinden beim nächsten Schritt.

Einstellungen: `debug.whyHere`, `debug.whyHere.depth`

#### Bedingungen vorausschauen

- Beim Halt stehen an den kommenden `if`, `while` und `case` derselben Routine (bis `debug.predictConditions.lines` Zeilen voraus, Vorgabe 20) die vorhergesagten Ergebnisse, als Vorhersage gekennzeichnet: `⟨= False · FOnline⟩` (der entscheidende Teil), bei `case` `⟨→ smManual⟩`.
- Der Zweig, der übersprungen wird, ist blass gezeichnet, bei `case` alle anderen Zweige; der Text bleibt lesbar (`debug.predictConditions.dimSkipped`).
- Vorhergesagt wird nur, was sich aus dem jetzigen Zustand ergibt: keine Zuweisung an eine beteiligte Variable dazwischen (auch `var`/`out`-Argumente, `Inc`/`Dec`), kein Aufruf dazwischen bei Feldern und globalen Variablen, kein `Exit`, `raise`, `goto`, `Break` oder `Continue`.
- Aufrufe und Getter in der Bedingung wertet die Vorhersage nie aus; sie zählt nur, wenn der Kurzschluss ohne den Aufruf entscheidet.
- Ein Klick auf einen Hinweis öffnet das Menü „Vorhersage für diese Sitzung aus“. Hinweise und Blässe verschwinden beim nächsten Schritt.

Einstellungen: `debug.predictConditions`, `debug.predictConditions.dimSkipped`, `debug.predictConditions.lines`

#### Werte ändern

- Im Debug-Hover steht unter dem Wert „Ändern …“, bei `True`/`False` zusätzlich „Auf False setzen“ bzw. „Auf True setzen“. Im Editor ändert F2 (oder „Atlas: Wert ändern“ im Kontextmenü unter Debuggen) den Bezeichner an der Schreibmarke; ohne angehaltenes Programm geht F2 an die IDE.
- Die Eingabe passt zum Typ: Zahlen mit Bereichsprüfung (`Byte` 0..255, auch `$FF`), Gleitkomma mit Komma oder Punkt, Zeichen und Strings ohne Hochkommas, Aufzählungen als Auswahlliste (bei `{$SCOPEDENUMS ON}` mit Typpräfix), Mengen mit einem Häkchen je Wert, `TColor` mit „Farbe wählen …“ (auch `#RRGGBB`). Ungültiges steht rot unter dem Feld, „Ändern“ ist dann aus; Enter übernimmt, Esc bricht ab.
- Eine Eigenschaft mit Setter ändert Atlas erst nach Rückfrage („Setter SetBetrag wird aufgerufen“), über den Aufruf des Setters. Nur lesbare Eigenschaften lehnt der Dialog ab.
- Geänderte Werte stehen bis zum nächsten Schritt am Zeilenende in der Warnfarbe mit dem alten Wert: `Betrag = 150 (vorher 125)`. „Rückgängig (vorher 125)“ im Hover oder „Atlas: Geänderten Wert zurücksetzen“ setzt den alten Wert, solange nicht weitergelaufen wurde.

Einstellungen: `debug.editValues`

#### Debug-Hover aufklappen

- Objekte, Records und Arrays tragen im Debug-Hover ▸ vor dem Ausdruck; ein Klick klappt sie auf. Die Zeilen stehen eingerückt als `Name = Wert` (Felder, Elemente mit Index `[0]`), zusammengesetzte Kinder und Objekte klappen weiter auf. Jede Ebene wird erst beim Aufklappen ausgewertet; antwortet der Debugger verzögert (Win64), steht dort „wird ausgewertet …“, bis der Wert kommt, die IDE bleibt bedienbar.
- Eigenschaften aus dem Atlas-Index stehen als „auswerten“: Getter können Nebenwirkungen haben und laufen erst nach dem Klick.
- Höchstens 100 Kinder je Ebene (`debug.hoverMaxChildren`), dann „weitere 100 …“. Ist ein Array zu lang für eine Antwort des Debuggers, wertet Atlas die sichtbaren Elemente einzeln aus.
- Seit dem vorigen Halt (gleicher Thread, gleiche Methode) geänderte Werte sind hinterlegt, der alte Wert steht gedimmt dahinter: `Umsatz = 1250,00 ← 980,00`. Das gilt auch für aufgeklappte Kinder; das Ende der Debug-Sitzung leert den Speicher.
- Mit der Maus über dem Tooltip wählen ↑ und ↓ eine Zeile, → klappt auf, ← zu. Die Aktionen unter dem Wert (Kopieren, mit Umschalt `Ausdruck = Wert`; Anheften; Ändern …; Beobachten öffnet „Auswerten“ mit dem Ausdruck) wirken auf die gewählte Zeile; ein Rechtsklick auf eine Zeile bietet sie als Menü an.
- Mehr als 12 Zeilen scrollen im Tooltip.

Einstellungen: `debug.hoverExpand`, `debug.hoverMaxChildren`, `debug.hoverChanges`

#### Werte anheften

- Im Debug-Hover steht unter dem Wert „Anheften“. Der Ausdruck steht danach bei jedem Halt als gerahmtes Feld `Summe = 125 ✕` am Ende seiner Zeile, hinter den Werten im Editor.
- Seit dem vorigen Halt geänderte Werte stehen in der Warnfarbe.
- Angeheftete Ausdrücke gelten je Projekt und bleiben über Debug-Sitzungen erhalten; ein Klick auf ✕ löst sie dauerhaft.
- Ausgewertet wird ohne Nebenwirkungen: Ausdrücke mit Aufrufen bleiben `?`. Höchstens 100 je Projekt.

Einstellung: `debug.pinnedValues`

#### „kein Zugriff auf Wert“ erklärt

- Liefert der Debugger für eine Variable nur „Inaccessible value“ oder „… wegen der Optimierung nicht …“, steht im Hover und in den Werten im Editor `‹kein Zugriff›`.
- Der Hover nennt die Ursache (Start in Release, `$D-`/`$L-`, `$O+` mit Register, Lebensdauer der Variablen, `inline`, RTL/VCL ohne Debug-DCUs) und woher der Schalter kommt.
- Er bietet Korrekturen mit Vorschau:
  - mit Debug neu starten
  - `{$OPTIMIZATION OFF}`/`ON` um die Routine
  - `{$O-}` am Unit-Anfang
  - Debug-DCUs verwenden
- Ohne Treffer zeigt er die geprüften Punkte.

Einstellungen: `debug.explainUnavailable`

#### Vervollständigung in Debugger-Dialogen

- In „Auswerten/Ändern“ (Strg+F7), im Ausdruck einer Überwachung und in Bedingung und Log-Ausdruck eines Haltepunkts bietet das Atlas-Popup Namen aus dem passenden Gültigkeitsbereich an:
  - lokale Variablen, Parameter, Felder von `Self`, Units und globale Namen
  - nach `.` die Elemente
- Gültigkeitsbereich ist bei angehaltenem Programm der Ausführungspunkt, im Haltepunktdialog dessen Zeile, sonst die Cursorzeile im Editor.
- Pfeil nach unten im leeren Feld zeigt die letzten 20 Ausdrücke des Projekts.

Einstellungen: `debug.completionInDialogs`

<a id="window-atlasevaluate"></a>
#### Fenster „Auswerten“

- Andockbares Fenster „Atlas: Auswerten“ mit mehreren Ausdrücken, die bei jedem Halt neu ausgewertet werden.
- Seit dem letzten Halt geänderte Werte sind hervorgehoben.
- Objekte, Records und Arrays klappen zu ihren Feldern auf (aus dem Atlas-Index, jedes einzeln ausgewertet).
- Der gewählte Wert steht als Text mit sichtbaren Steuerzeichen, als Zeilen einer `TStrings`, als eingerücktes JSON oder als Hex da.
- Während die Werte nach und nach eintreffen, bleibt das Fenster bedienbar: Der Baum wird nur dort geändert, wo sich etwas geändert hat, statt jedes Mal neu aufgebaut zu werden; aufgeklappte Zeilen, Auswahl und Bildlaufposition bleiben stehen. Baum und Ansicht füllen das Fenster in jeder Größe, die Tastenhilfe umbricht nach Breite.
- „Nebenwirkungen erlauben“ (aus) lässt Funktionsaufrufe und Getter zu.

| Bedienung | Wirkung |
|---|---|
| „Ändern …“ | setzt einen neuen Wert |
| Strg+Enter | heftet einen Ausdruck fürs Projekt fest |
| Pfeil nach unten im leeren Feld | zeigt die letzten 50 Ausdrücke |
| Strg+F7 | öffnet das Fenster mit dem Ausdruck unter dem Cursor |
| Umschalttaste oder Befehl „Auswerten/Ändern (IDE-Dialog)“ | der Dialog der IDE kommt |

Einstellungen: `debug.evaluateWindow`, `debug.evaluateWindow.replaceCtrlF7`

<a id="window-atlasvariables"></a>
#### Fenster „Variablen“

- Andockbares Fenster „Atlas: Variablen“ (Atlas-Menü) mit drei Reitern, bei jedem Halt neu ausgewertet:
  - **Autos:** Variablen, Felder und einfache Ausdrücke der aktuellen Anweisung und nach einem Schritt auch der vorigen, aus dem Syntaxbaum. Aufrufe (auch Funktionen und Getter ohne Klammern) stehen nicht darin, nur ihre Argumente und das Objekt davor: Bei `Betrag := LeseBetrag(S);` sind es `Betrag` und `S`.
  - **Lokal:** `Self`, Parameter, `Result`, lokale Variablen und Inline-Variablen, die an der Zeile schon gelten.
  - **Überwachung:** eigene Ausdrücke, je Projekt gespeichert; sie kommen mit dem Projekt wieder.
- Ausgewertet wird ohne Nebenwirkungen; Werte klappen zu ihren Feldern auf wie im Fenster „Auswerten“, seit dem letzten Schritt geänderte Werte sind hervorgehoben.
- Suche im gezeigten Reiter nach Name oder (mit „In Werten“) nach Wert. Mit „Unterelemente“ klappt Atlas Knoten bis `debug.variablesWindow.searchDepth` Ebenen selbst auf und hört nach `debug.variablesWindow.searchLimit` Auswertungen auf. Gezeigt werden Treffer (fett), ihr Pfad und ihre Unterelemente; unten steht die Zahl der Treffer. Ein Wert zählt nur bei einfachen Werten: Bei einer Suche nach „Berlin“ ist `Kunde.Adressen[1].Ort` der Treffer, nicht `Kunde`.
- Autos und Lokal brauchen den Atlas-Server; die Überwachung geht ohne.

| Bedienung | Wirkung |
|---|---|
| Strg+F | ins Suchfeld |
| Strg+W | Ausdruck der Zeile als Überwachung hinzufügen |
| Strg+C | Wert kopieren |
| Strg+Umschalt+C | Ausdruck kopieren |
| F2 | Wert ändern (mit `debug.editValues`, wie „Ändern …“ im Debug-Hover) |
| Entf (Reiter Überwachung) | Überwachung entfernen |
| Enter im Eingabefeld des Reiters Überwachung | Ausdruck überwachen |

Einstellungen: `debug.variablesWindow`, `debug.variablesWindow.searchDepth`, `debug.variablesWindow.searchLimit`

### Ereignisprotokoll

<a id="window-atlasdebugeventlog"></a>
- andockbares Fenster „Atlas: Ereignisprotokoll“ mit Ausgaben (`OutputDebugString`), Haltepunkt-Meldungen, Modulen, Threads, Logpunkten sowie Start und Ende der Sitzung
- Spalten Zeit (relativ zum Start), Art, Thread, Text
- Filter nach Art und Text: Wörter (jedes muss vorkommen) oder `/regulärer Ausdruck/`; „Filter merken“ hält ihn je Projekt in der Auswahl
- Farben nach Muster, etwa `[FEHLER]` rot, `[WARN]` gelb
- Doppelklick oder Enter springt zu `Datei.pas(123)`, `Datei.pas:123` oder `Unit.Routine`
- Kontextmenü: Zeile kopieren, als Textdatei speichern, leeren

Einstellungen: `debug.eventLog`, `debug.eventLogColors`

### Logpunkte

- Umschalt+F5 oder „Atlas: Logpunkt setzen“ (Atlas-Menü, Kontextmenü des Editors) an der Cursorzeile bzw. nach Rechtsklick in die Rinne an deren Zeile
- Text mit Platzhaltern: `x={x}`, `Summe {Summe:0.00}`; Formatangaben `d` (ganze Zahl), `x` (hexadezimal), Muster mit `0` oder `#` (`FormatFloat`), sonst wie in `Format` (`.2f`); `{{` und `}}` sind Klammern im Text
- Bedingung (`{Summe} > 1000`) und „nur die ersten N Treffer“; Fehler im Text zeigt der Dialog mit Stelle
- ein gewöhnlicher Haltepunkt an der Zeile wird zum Logpunkt; „Entfernen“ löscht ihn
- im Ereignisprotokoll eine Zeile der Art Logpunkt mit Präfix und Ort, etwa `[LOG] x=42 · Unit1.pas:12`; Doppelklick springt zur Zeile
- Raute in der Rinne mit Text und Bedingung im Tooltip
- „Alle Logpunkte aus“, „… an“, „… löschen“ betreffen nur die Haltepunktgruppe `Atlas.Logpunkte`

Einstellungen: `debug.logpoints`, `debug.logpointPrefix`

### Kein Quelltext

- Hält der Debugger in einer Routine ohne Quelltext (die IDE zeigt das CPU-Fenster), erscheint oben rechts ein kleines Fenster ohne Fokus: Routine, Modul, Adresse, Unit und Grund
- Gründe: Debug-DCUs aus (Bibliothek von Delphi), Unit mit `{$D-}` übersetzt, nur DCU/BPL vorhanden, Quelltext nicht im Suchpfad, Systemcode (Windows)
- Auswege je nach Grund: „Debug-DCUs einschalten und neu bauen“ (nur in der Konfiguration Debug, mit Rückfrage; die Sitzung endet, danach baut und startet Atlas), „Zurück zum eigenen Code“ (bis zur Rückkehr in eigenen Code), „Quelltext suchen …“ (Ordner wird für das Projekt gemerkt, die Unit öffnet sich), „CPU-Fenster behalten“
- „Für diese Unit nicht mehr zeigen“ ergänzt `debug.noSourcePage.ignoredUnits`
- Mit „Nur eigener Code“ (`debug.justMyCode`) erscheint das Fenster nur bei Exceptions

Einstellungen: `debug.noSourcePage`, `debug.noSourcePage.ignoredUnits`

### Neu starten

- „Atlas: Neu starten“ mit Strg+Umschalt+F2, im Atlas-Menü oder in der Befehlspalette
- Schritte: Beenden (nur bei laufendem Programm), Bauen (nur bei Änderungen seit dem letzten Bau), Starten, zurück an die Stelle im Editor
- Oben rechts eine kleine Leiste ohne Fokus mit den Schritten und ihrer Dauer, etwa „Beenden 0,3 s ✓ · Bauen 2,1 s ✓ · Starten …“
- Scheitert ein Schritt, bricht der Ablauf ab und die Leiste nennt den Grund
- Mit `debug.restart.reenableBreakpoints` schaltet Atlas vor dem Start Haltepunkte wieder ein, die beim Start der letzten Sitzung an waren

Einstellungen: `debug.restart`, `debug.restart.reenableBreakpoints`

### Leck- und Absturzberichte (#74)

- Bericht kopieren, dann Atlas > „Absturz- oder Leckbericht einfügen …“ (auch in der Befehlspalette): Atlas liest FastMM-Logs (FullDebugMode), die Meldung von `ReportMemoryLeaksOnShutdown`, Berichte von madExcept, EurekaLog 6/7 und JclDebug und die Meldung einer Exception allein („Zugriffsverletzung bei Adresse … in Modul …“)
- Die Meldungsansicht zeigt den Aufrufstapel des Absturz-Threads und der übrigen Threads bzw. je Leckgruppe (gleiche Klasse, gleicher Stapel) den Stapel; Zeilen im Projekt springen per Doppelklick in den Quelltext
- Im Editor stehen Diagnosen an den Stellen: je Leckgruppe eine Warnung an der Erzeugungsstelle („Leck: TStringList × 2 (40 Bytes) wird hier erzeugt“), beim Absturz eine Warnung an der Absturzstelle und Hinweise an den übrigen eigenen Zeilen des Stapels; Quelle ist das Werkzeug (FastMM, madExcept, …)
- Stapelzeilen ohne Debug-Informationen löst Atlas über die Map-Datei neben der EXE der Konfiguration Debug auf (Linker-Option „Map-Datei: Detailliert“); passt die Map nicht zur EXE (anderer Einsprungpunkt oder andere Codelänge), sagt Atlas es
- „Markierungen des Laufzeitberichts entfernen“ nimmt die Diagnosen wieder weg; ein neuer Bericht ersetzt den alten
- Für KI-Assistenten gibt es dieselbe Auswertung als MCP-Werkzeuge `analyze_report` und `resolve_address`

### Erneut an Prozess anhängen

- Hängt sich die IDE an einen laufenden Prozess (Start › An Prozess anhängen …), merkt Atlas Pfad und Name der EXE für die Projektgruppe
- „Erneut an <Name> anhängen“ im Menü Start, in der Befehlspalette und mit Umschalt+Alt+P:
  - genau ein laufender Prozess mit gleichem Pfad: sofort angehängt, ohne Dialog
  - mehrere, oder nur gleicher Name an anderem Ort (andere Version): Auswahl mit PID, Startzeit und Befehlszeile
  - keiner: Angebot, auf den Start zu warten
- „Anhängen, sobald gestartet …“ im Menü Start und in der Befehlspalette: EXE wählen (Vorgabe: zuletzt gemerkte, sonst Ausgabedatei des aktiven Projekts); Atlas fragt die Prozessliste im Hintergrund ab und hängt sich beim Start sofort an
- Während des Wartens zeigt das Statusfeld „Warte auf … (Abbrechen)“; ein Klick bricht ab, ebenso das Schließen oder Wechseln der Projektgruppe
- Endet ein angehängter Prozess, bietet das Statusfeld an, sich beim nächsten Start wieder anzuhängen
- Die ersten Millisekunden des Programms (Initialisierung) verpasst das Warten; wer sie braucht, startet über die Startparameter des Projekts oder eine Host-Anwendung
- Nur lokale Prozesse; Prozesse anderer Benutzer und Dienste brauchen eine IDE mit Administratorrechten

Einstellungen: `debug.reattach`, `debug.reattach.key`, `debug.reattach.waitIntervalMs`

### Mehrere Programme gemeinsam debuggen

- Startverbünde stehen in der Projektdatei `.atlas` unter `launchGroups`, Pfade ab ihrem Ordner:

```json
"launchGroups": [{"name": "Server + Client", "items": [
  {"project": "Server\\Server.dproj", "profile": "Lokal", "wait": "port", "value": 8080, "timeout": 20},
  {"project": "Client\\Client.dproj", "debug": false}]}]
```

- je Projekt: Startprofil (`profile`, sonst die Startoptionen des Projekts), mit Debugger (`debug`, Vorgabe ja) und die Wartebedingung vor dem nächsten (`wait`: `seconds` mit `value` Sekunden, `port` bis `localhost:value` Verbindungen annimmt, `window` bis das Programm ein sichtbares Hauptfenster hat; höchstens `timeout` Sekunden, Vorgabe 30)
- „Atlas: Startverbünde …“ im Atlas-Menü und in der Befehlspalette zeigt die Verbünde mit ihren Projekten, setzt den aktiven Verbund (je Projektgruppe, persönlich) und startet ihn; „In .atlas bearbeiten“ öffnet die Projektdatei
- F9 ohne laufende Sitzung startet den aktiven Verbund, sonst startet die IDE wie gewohnt
- Atlas baut zuerst die geänderten Projekte und startet dann eins nach dem anderen; eine Leiste oben rechts zeigt den Lauf, etwa „Server ✓ · Client startet …“
- Scheitert ein Bau oder Start oder läuft eine Wartezeit ab, hält der Lauf an und fragt „Trotzdem weiter“ oder „Alle beenden“
- Strg+F2 bzw. „Atlas: Startverbund beenden“ beendet alle Programme des Verbunds
- Das Statusfeld zeigt je Programm „läuft“, „angehalten“ oder „beendet“; ein Klick macht den nächsten Prozess des Verbunds zum aktuellen der IDE; hält der Debugger, nennt die Meldung den Prozess
- Grenzen: Mit Debugger gestartete Programme nutzen die Parameter des Startprofils, Arbeitsordner und Umgebung aber aus den Startoptionen der IDE; nur Projekte der offenen Projektgruppe

Einstellungen: `debug.launchGroups`

### Exceptions

<a id="window-atlasdebugexceptions"></a>
#### Exception-Verlauf

- andockbares Fenster „Atlas: Exceptions“ mit jeder Exception der Debug-Sitzung (Uhrzeit, Klasse, Meldung aus dem Dialog der IDE, Anzahl gleicher Exceptions am gleichen Ort, Ort, Thread)
- Filter nach Klasse und Text
- Enter springt zur Zeile
- Strg+C kopiert Klasse, Meldung und Aufrufstapel
- „Klasse künftig ignorieren“ setzt bei dieser Klasse still fort

Einstellungen: `debug.exceptionHistory`

#### Nur eigener Code

- Nach einer Exception in Bibliothekscode springt Atlas zur ersten eigenen Zeile im Aufrufstapel und markiert sie.
- F7 in Code ohne Quelltext läuft bis zur Rückkehr weiter.
- Der Exception-Verlauf zeigt Bibliotheksrahmen abgeschwächt und fasst sie zu „… 7 Bibliotheksrahmen“ zusammen.

Einstellungen: `debug.justMyCode`, eigener Code = Projektordner und `debug.ownCodeFolders`

#### Exception-Leiste statt Dialog

- Hält der Debugger wegen einer Exception, zeigt eine Leiste oben im Editor Klasse, Meldung, Thread, wie oft sie an dieser Stelle kam, und die erste eigene Zeile („3 Ebenen ausgeblendet“).
- Knöpfe:
  - Anhalten (F8/Esc)
  - Fortsetzen (F9)
  - Klasse ignorieren
  - Nur an dieser Stelle ignorieren (Klasse + Unit + Zeile je Projekt, beim nächsten Mal still fortgesetzt)
  - Meldung kopieren
- In Delphi 12 und 13 schließt Atlas dafür den Dialog der IDE, sonst bleibt er und die Leiste kommt danach.

Einstellungen: `debug.exceptionBanner`, aus, bis die Studie zu #783 positiv ist

#### Zugriffsverletzung erklärt

- Hält der Debugger wegen einer Zugriffsverletzung in eigenem Code, zerlegt Atlas die Anweisungen der Zeile in Zugriffsketten (`Auftrag.Kunde.Adresse.Ort`, `Liste[I].Name`, `Self.FDaten^`) und wertet sie von links aus.
- Die Exception-Leiste:
  - sagt „`Auftrag.Kunde` ist nil“ mit dem Feld an der Leseadresse („Zugriff auf Feld `FAdresse` (Versatz $1C)“, vom Debugger bestätigt oder geschätzt)
  - listet die geprüften Glieder mit ✓/✗
  - bietet „Wo wird `Kunde` zugewiesen?“, „Ausdruck auswerten“ und „Erklärung kopieren“
- Erkannt werden auch freigegebene Objekte (Füllmuster des Speichermanagers wie `$80808080` und `$FEEEFEEE`) und ein Index außerhalb eines dynamischen Arrays.
- Ohne eindeutige Ursache steht „Ursache nicht eindeutig“.
- Das schuldige Glied ist im Editor unterstrichen, bis weitergelaufen wird.
- Getter und Funktionsaufrufe wertet Atlas nur mit `debug.explainAccessViolation.allowCalls` aus.
- Dahinter steht, in welchem Modul die Fehleradresse liegt: „in deinem Programm“, „in vcl290.bpl (RTL/VCL)“, „in ntdll.dll (Windows)“ oder „in Fremd.dll (keine Debug-Infos)“. Hält der Debugger nicht in eigenem Code, nennt Atlas nur das Modul und die letzte eigene Stelle aus dem Aufrufstapel (`debug.moduleOfAddress`).
- Ohne Exception-Leiste steht das Ergebnis in den Meldungen.

Schalter: `debug.explainAccessViolation`, `debug.moduleOfAddress`.

### Threads

#### Was wartet worauf?

- Hängt ein Programm, hält man es an (Start > Programm Pause) und wählt Atlas > „Was wartet worauf?“.
- Atlas liest die Aufrufstapel aller Threads und zeigt im Ergebnisfenster je Thread Kennung, Namen (`TThread.NameThreadForDebugging`), Wartepunkt und die erste eigene Codezeile, etwa „Thread 7 „Worker“: wartet in TThread.Synchronize, bei TWorker.Execute (Unit2.pas:30)“.
- Als Wartepunkt gilt die Warte-Routine über der ersten eigenen Zeile: `TThread.WaitFor`, `TThread.Synchronize`, `TMonitor.Enter`/`Wait`, Critical Section, Ereignis (`TEvent.WaitFor`), `Sleep` oder ein Handle (`WaitForSingleObject`, `WaitForMultipleObjects`); die Nachrichtenschleife zählt als „wartet auf Nachrichten“.
- Darüber stehen erkannte Muster:
  - Der Hauptthread wartet in `TThread.WaitFor` (etwa im Destruktor eines Threads), ein Thread wartet in `Synchronize` auf ihn: Verklemmung, siehe Regel `synchronize-in-destructor`.
  - Ein Thread wartet in `Synchronize`, der Hauptthread hängt an einer Sperre.
  - Mehrere Threads warten an derselben Stelle auf eine Sperre.
  - Alle Threads warten, keiner läuft.
- Doppelklick wechselt zum Thread und springt auf seine erste eigene Codezeile.
- Wer eine Sperre (`TMonitor`, Critical Section) hält, liefert der Debugger nicht; Atlas nennt nur die Wartenden.

Schalter: `debug.deadlocks`.

<a id="window-atlasdebugcallstack"></a>
#### Atlas-Aufrufstapel

- Atlas > „Atlas-Aufrufstapel“ öffnet ein andockbares Fenster, das bei jedem Halt den Aufrufstapel des aktuellen Threads zeigt: je Rahmen Routine mit Parametern und `Unit.pas:Zeile`.
- Aufeinanderfolgende Rahmen aus RTL, VCL und Bibliotheken stehen zugeklappt als „▸ 7 Aufrufe in VCL“, daneben erste und letzte Routine; Klick, Enter oder Doppelklick klappt auf.
- Parameter heißen wie in der Deklaration (der Server liest die Routine an der Zeile des Rahmens). Atlas wertet sie aus und zeigt Ersatztexte der Visualisierer, Strings in Anführungszeichen und Objekte mit Klasse und `Name`-Feld, etwa `AKunde = TKunde 'Meier'`.
- Die Suche (Strg+F) findet Routine, Unit oder Wert, auch in zugeklappten Gruppen („▸ 7 Aufrufe in VCL · 1 Treffer“); Treffer stehen fett.
- Klick bzw. Enter auf einem Rahmen springt zur Zeile.
- „Kopieren“ (Strg+C) gibt den Stapel als Text oder als Markdown-Liste (`` `Unit.pas:Zeile` ``) in die Zwischenablage, wahlweise nur eigener Code.
- „Mit letztem Halt vergleichen“ stellt den Stapel des letzten Halts an derselben Stelle daneben und markiert geänderte Rahmen und Werte mit „≠“. Atlas merkt sich je Debug-Sitzung höchstens 20 Stellen, solange das Fenster offen ist.
- Grenzen: Die Werte tieferer Rahmen wertet Atlas über die Adresse aus (Objekte und Zeiger); einfache Werte zeigt der Rahmentext der IDE schon. Rahmen anonymer Methoden und Routinen ohne Parameterliste im Implementierungsteil bekommen keine Namen.

Schalter: `debug.callStackWindow` (aus: der Aufrufstack der IDE bleibt, wie er ist), `debug.callStackWindow.evaluateParams`.

<a id="window-atlasdebugparallelstacks"></a>
#### Parallele Aufrufstapel

- Atlas > „Parallele Aufrufstapel“ öffnet ein andockbares Fenster, das bei jedem Halt die Aufrufstapel aller Threads als Baum zeigt, vom Thread-Start (Wurzel) bis zum obersten Rahmen.
- Gleiche Rahmen (gleiche Routine an gleicher Stelle) stehen einmal da mit der Zahl der Threads, etwa „TWorker.Execute (Unit2.pas:30) · 10 Threads“; der Baum verzweigt dort, wo sich die Stapel trennen.
- Knoten des aktuellen Threads stehen fett. Stehen alle Threads eines Knotens in einer Warte-Routine (`TMonitor.Enter`, `WaitForSingleObject`, `Sleep` …), steht „wartend“ dahinter, in der Warnfarbe; die Liste der Routinen ist einstellbar (`debug.parallelStacks.waitRoutines`).
- Filter „Nur eigener Code“ blendet Rahmen aus RTL, VCL und Bibliotheken aus, „Wartend“ zeigt nur wartende Threads.
- Unten stehen die Threads des gewählten Knotens. Enter oder Doppelklick wechselt zum Thread (bei mehreren über eine Auswahlliste) und springt zur Zeile.
- Ab `debug.parallelStacks.maxThreads` Threads (Vorgabe 64) liest Atlas die Stapel abschnittsweise und zeigt den Baum dazwischen, damit die IDE bedienbar bleibt.

Schalter: `debug.parallelStacks`, `debug.parallelStacks.waitRoutines`, `debug.parallelStacks.maxThreads`.

<a id="window-atlasdebugleaks"></a>
#### Atlas-Lecks

- Endet ein im Debugger gestartetes Programm mit Speicherlecks, liest Atlas den Bericht ein: das Meldungsfenster von `ReportMemoryLeaksOnShutdown` (Text des Fensters, kein Klick) oder die Logdatei von FastMM4/FastMM5 neben der EXE, wenn sie nach dem Start geschrieben wurde. Eine Logdatei mit Aufrufstapeln (FullDebugMode) geht vor.
- Das andockbare Fenster „Atlas-Lecks“ (Atlas > „Atlas-Lecks“) zeigt je Klasse die Zahl der Lecks. Neue Klassen und gestiegene Zahlen gegenüber dem letzten Lauf derselben Konfiguration stehen fett („neu“, „+2 seit dem letzten Lauf“); der Stand liegt in `.atlas-local` neben der .dproj.
- Ohne Aufrufstapel stehen unter jeder Klasse die Stellen im Projekt, die sie erzeugen (`TKlasse.Create…`), mit Bewertung: nie freigegeben, Rückgabe an den Aufrufer, als Argument weitergereicht, Feld frei im Destruktor, Owner, lokal freigegeben, nicht im Programm (Testunits). Die dringlichsten stehen oben.
- Mit Aufrufstapeln stehen dort die Erzeugungsstellen aus dem Bericht, gleiche Stapel zusammengefasst.
- String- und unbekannte Lecks folgen meist aus geleakten Objekten mit solchen Feldern; das Fenster sagt es dazu.
- „Als bekannt markieren“ merkt eine Klasse, „Bekannte ausblenden“ blendet sie aus. Enter oder Doppelklick springt zur Stelle.

Schalter: `debug.leakReport`, `debug.leakReport.compare`, `debug.leakReport.window`.

#### Threads im Quelltext

- Beim Halt steht im Rand an jeder Zeile, an der ein anderer Thread mit seinem obersten eigenen Rahmen steht, ein Zeichen mit der Anzahl; bei acht wartenden Workern an derselben Zeile also „8“. Den aktuellen Thread zeigt die IDE wie bisher.
- Der Tooltip nennt je Thread Kennung, Name und Wartepunkt („⚑ 4120 „Worker“ · wartet in TEvent.WaitFor“); die Links darunter wechseln zum Thread und springen auf seine Zeile.
- Rechtsklick in den Rand, dann Atlas > Debuggen > „Thread markieren“: Markierte Threads tragen ⚑ und stehen im Tooltip, in Auswahllisten und in den parallelen Aufrufstapeln (Kontextmenü „Thread markieren“) oben. Die Markierung gilt für die Sitzung und folgt der Thread-ID. Stehen an der Zeile mehrere Threads, wählt man aus einer Liste; ohne Thread an der Zeile gilt der aktuelle.
- Experimentell (`debug.threadFreeze`, Vorgabe aus): „Thread einfrieren“, „Thread auftauen“ und „Alle Threads auftauen“. Ein eingefrorener Thread läuft beim Fortsetzen nicht weiter; sein Zeichen ist grau, die Statusleiste von Atlas zeigt „2 Threads eingefroren“ (Klick taut alle auf). Atlas hält den Thread mit `SuspendThread` an; das geht nur bei Programmen auf diesem Rechner. Am Ende der Sitzung und beim Abschalten taut Atlas alle auf.

Schalter: `debug.threadsInSource`, `debug.threadFreeze`.

#### Herkunft eingereihter Methoden *(experimentell)*

- Hält das Programm in einer anonymen Methode, die mit `TThread.Queue`, `TThread.Synchronize`, `TThread.ForceQueue`, `TTask.Run`, `TTask.Create` oder `TParallel.For` gestartet wurde, zeigt der Aufrufstapel der IDE nur `CheckSynchronize` bzw. den Thread-Pool. Atlas zeigt dann im Ergebnisfenster „Eingereiht mit TThread.Queue von Thread 4120“ und darunter den Stapel der Einreihung; Rahmen der Bibliothek stehen zusammengefasst („5 Rahmen der Bibliothek“), Doppelklick springt zur Zeile.
- Dafür setzt Atlas beim Start der Sitzung auf jede Aufrufstelle im Projekt einen Haltepunkt der Gruppe Atlas.Herkunft. Hält das Programm dort, merkt Atlas Thread und Stapel und setzt sofort fort. Ein Haltepunkt des Benutzers an derselben Zeile bleibt und hält wie gewohnt.
- Zugeordnet wird der Reihe nach: Der Halt in der Methode einer Aufrufstelle bekommt die älteste noch offene Einreihung dieser Stelle. Je Aufrufstelle merkt Atlas die letzten `debug.asyncOrigin.maxPerSite` (Vorgabe 20).
- Erfasst werden nur Aufrufe mit Klassennamen (`TThread.Queue(…)`), ein `Synchronize(…)` in einer Methode eines Threads nicht.
- Das Anhalten an jeder Aufrufstelle bremst das Programm; die Statusleiste von Atlas zeigt „Herkunft: 12 Aufrufstellen“ in Gelb, solange die Haltepunkte stehen.

Schalter: `debug.asyncOrigin`, `debug.asyncOrigin.maxPerSite`.
