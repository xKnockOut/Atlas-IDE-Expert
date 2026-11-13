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

### Fehlschlag an der Assert-Zeile (#1771)

- Ein fehlgeschlagener Test steht nicht mehr am Methodenkopf, sondern an der Anweisung, die fehlschlug: Wellenlinie über der Anweisung, dahinter grau „erwartet 4, erhalten 3“.
- Die Zeile kommt aus dem Stacktrace des Berichts (DUnitX mit JclDebug oder madExcept). Bricht der Test mit einer Ausnahme ab, ist es die auslösende Anweisung.
- Ohne Zeilen im Stacktrace sucht Atlas im Rumpf den einen Assert, dessen erwarteter Wert zum Bericht passt (`Assert.AreEqual(4, …)` bei „Expected 4 but got 3“); hat der Rumpf nur einen Assert, gilt dieser. Passen mehrere, bleibt es beim Methodenkopf.
- Eingefügte Zeilen nimmt der Eintrag mit wie jeder Befund; die Zeile in der Meldungsansicht springt zur Anweisung.
- Der kurze Text erscheint wie der Fehlertext am Zeilenende (`editor.inlineDiagnostics`).

Einstellungen: `tests.failureAtAssert`, `tests.failureInline`

### Erwartet und erhalten vergleichen (#1779)

Aufruf: *Atlas*-Menü, Befehlspalette, Kontextmenü einer Testunit (*Atlas › Tests*).

- Zeigt den Fehlschlag des Tests am Cursor (bei einem `[TestCase]` den ersten fehlgeschlagenen Fall), sonst den zuletzt gemeldeten, in zwei Spalten: links erwartet, rechts erhalten.
- Abweichende Zeichen sind rot bzw. grün hinterlegt; Zeilen, die es nur auf einer Seite gibt, ganz, gegenüber eine graue Lücke.
- Zeilenenden (`↵`, `␍↵`, `␍`), Tabs (`→`) und Leerzeichen am Zeilenende (`·`) sind sichtbar; ein Unterschied nur darin fällt so auf.
- Sind beide Werte JSON bzw. XML, rückt Atlas sie vorher gleich ein; der Unterschied steht dann in seiner eigenen Zeile.
- Werte, die mit „...“ enden, tragen „(gekürzt)“ im Spaltenkopf.
- „Erhalten kopieren“ legt den erhaltenen Wert in die Zwischenablage, etwa um den erwarteten Wert im Test zu aktualisieren; Esc schließt.
- Nur für Fehlschläge, deren Bericht erwarteten und erhaltenen Wert nennt.

Einstellungen: `tests.compare`, `tests.compare.format`

### Testfall aus der Unit anlegen (#1226)

Aufruf: Code-Aktion (Alt+Enter) an einer Methode oder Routine, im Rumpf oder an der Deklaration; im Rumpf auch `/test`.

- Atlas findet die Testunit (Muster `testUnits.pattern`) und trägt einen Entwurf der Testmethode in die Testklasse ein, die getestete Unit kommt ins uses.
- Der Entwurf bereitet je Parameter eine Variable mit Platzhalter vor (`0`, `''`, `False`, `nil`, `Default(T)`), ruft die Methode über das Objekt der Testklasse (ein Feld vom Typ der Klasse), über die Klasse (Klassenmethoden) oder über ein lokales Objekt mit `try … finally` auf und prüft Ergebnis und `var`/`out`-Parameter mit Platzhaltern passend zum Typ (`Assert.AreEqual`, mit Toleranz bei Gleitkomma, `Assert.IsTrue`, `Assert.IsNotNull`).
- Ein `Assert.Fail` am Ende hält den Entwurf rot, bis die erwarteten Werte stimmen.
- Fehlt die Testunit, legt Atlas sie wie *DUnitX-Testunit anlegen* an (Fixture, Setup/TearDown, Eintrag in `.dpr` und `.dproj`) und setzt den Entwurf an die Stelle des leeren Tests.
- Private, geschützte und nur im implementation-Teil deklarierte Routinen sind von der Testunit aus nicht aufrufbar; für sie entsteht nur der Test mit `Assert.Fail`.

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
