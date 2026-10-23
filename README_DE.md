# Atlas IDE Expert

[![Spenden mit PayPal](https://img.shields.io/badge/Spenden-PayPal-00457C?logo=paypal)](https://www.paypal.com/paypalme/xKnockOut288)

*English version: [README.md](README.md).*

Atlas ist ein Experte für RAD Studio (Delphi/Object Pascal). Er ersetzt die eingebaute Code Insight durch eigene Fenster und ergänzt die IDE um Code-Analyse mit 170 74 73 75 75 76 75 76 75 71 76 75 73 75 75 75 73 4 76 279 Prüfregeln, Refactorings, Navigation, Formular-Unterstützung, Test- und Debug-Hilfen und eine eigene Willkommensseite. Die Daten liefert der **Atlas-Server**, ein eigener Language Server (LSP), der das Projekt indiziert und auch ohne IDE als Linter oder als MCP-Server für Claude Code läuft.

Funktionsumfang und Ausbaustufen stehen in den [Issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues).

## Auf einen Blick

| Bereich | Was Atlas mitbringt |
|---|---|
| [Schreiben](#schreiben) | Vervollständigung mit Detailpanel, Parameter-Hint, Code- und Postfix-Vorlagen, Schnellbefehle (`/uses`, `/extract`, …), Erzeugen-Menü, Formatierer |
| [Verstehen](#verstehen) | Hover mit Doku, Werten, Vererbung und Debugger-Werten, Typmarken, Code-Metriken, inaktive `{$IFDEF}`-Zweige |
| [Navigieren](#navigieren) | Brotkrumenleiste, Editorleiste, Gliederung, Definition einblenden, Datei schnell öffnen, Units suchen, Ergebnisfenster, Lesezeichen und Notizen |
| [Code-Analyse](#code-analyse) | 170 74 73 75 75 76 75 76 75 71 76 75 73 75 75 75 73 4 76 279 Prüfregeln (Fehler, Code-Smells, Sicherheit), Profile, Konfidenz, Baseline, Compilerprüfung nach dem Speichern, Linter für CI mit SARIF |
| [Refactorings und Code-Aktionen](#refactorings-und-code-aktionen) | Umbenennen samt Formularen, Signatur ändern, Methode extrahieren, Interface implementieren, Property erzeugen und viele Schnellkorrekturen (Alt+Enter) |
| [Formulare](#formulare) | Abgleich mit dem Designer, Komponenten in der Vervollständigung, Prüfungen zwischen Formular und Code |
| [Bauen, Testen, Debuggen](#bauen-testen-debuggen) | Release-Build-Wächter, DUnitX-Tests aus dem Editor, Startprofile, Werte im Hover beim Debuggen |
| [IDE-Komfort](#ide-komfort) | Willkommensseite, Befehlspalette, Benachrichtigungen, Änderungsmarken aus Git/SVN, abgesicherter Start |
| [Einstellungen](#einstellungen) | Jede Funktion einzeln abschaltbar, Optionsseite als Baum, teamweite Projektdatei `.atlas` |
| [Claude Code](#claude-code-und-mcp) | 19 MCP-Werkzeuge zum Lesen, Prüfen, Bauen, Testen und Umbenennen |

## Schnellstart

Voraussetzung ist RAD Studio bzw. Delphi ab Version 12. Fertige Pakete stehen unter [Releases](https://github.com/xKnockOut/Atlas-IDE-Expert/releases); Release 1.0.0 enthält das Plugin nur für Delphi 13.

**Weg A – mit Installer:**

1. `atlas-ide-expert-<Version>.zip` aus dem Release laden und entpacken.
2. `AtlasSetup.exe` starten. Er braucht keine Administratorrechte und findet die installierten Delphi-Versionen ab 12 selbst.
3. „Installieren“ wählen, danach Delphi starten.

Einzelheiten: [docs/Installation.md](docs/Installation.md).

**Weg B – heute: selbst bauen und das Package in der IDE installieren:**

1. Delphi ab 12 installieren und dieses Repository klonen.
2. `Atlas.groupproj` in Delphi öffnen und alle Projekte für **Win64** erstellen (*Alle erstellen*). Für die klassische 32-Bit-IDE zusätzlich `Atlas.IDE.Expert` für **Win32** erstellen.
3. In Delphi *Komponente › Packages installieren › Hinzufügen* und die BPL wählen: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl` für die klassische IDE (Delphi 12: `…290.bpl`), `Output\Win64\Debug\Bpl\…` für die 64-Bit-IDE. Den Server `Output\Win64\Debug\Bin\AtlasServer.exe` findet das Plugin dort von selbst.
4. Delphi einmal neu starten.

`AtlasSetup.exe` aus dem eigenen Build (`Output\Win64\Debug\Bin`) hilft hier nicht: Er sucht die BPLs in Unterordnern `Win32` bzw. `Win64` neben sich (Aufbau des Release-Pakets), der Build legt sie aber unter `Output\<Plattform>\Debug\Bpl` ab. Ohne gefundene BPL bietet er keine IDE an. Ausführlich: [Installation](#installation).

## Funktionen

Alles Folgende ist in `main` umgesetzt. Funktionen mit *(experimentell)* sind ab Werk aus und lassen sich unter *Tools › Optionen › Drittanbieter › Atlas* einschalten, sobald der Hauptschalter „Experimentell“ an ist. Die vollständige Beschreibung jeder Funktion steht in [docs/RAD-Studio.md](docs/RAD-Studio.md) und im [CHANGELOG](CHANGELOG.md).

### Schreiben

- **Vervollständigung** im eigenen Popup: Detailpanel mit eingefärbter Deklaration und Doku, Filter-Chips, unscharfe Suche, lernende Reihenfolge, Favoriten (Strg+D), Tippfehler-Vorschläge („Meintest du“), Vorschau im Editor, Hinweis `+ Unit` für noch nicht eingebundene Units
- **Passend zum Kontext:** Aufzählungswerte zuerst, Mengenelemente zum Abhaken, `case` mit allen oder fehlenden Werten, nur Typen nach `:`, Typargumente nach Constraints, vollständiger `inherited`-Aufruf, Feld- und Parameternamen in `FieldByName('`, Komponenten des Formulars, `Sender` mit passender Typumwandlung, gleichnamige Symbole aus verschiedenen Units, Helper-Methoden, uses-Liste mit Gruppen
- **Unbekannte Namen:** lokale Variable, Inline-Variable, Feld oder Methode direkt aus der Liste anlegen; Namensvorschläge aus dem Typ
- **Parameter-Hint** mit allen Überladungen, aktivem Parameter und Auswahl nach Argumenttypen
- **Vorlagen:** Code-Vorlagen (`tryf`, `forin`, `prop`, …), eigene `*.atlas-snippet`-Dateien, die Live Templates der IDE, klassenbewusste Vorlagen (`prop`, `create`, `free`) und Postfix-Vorlagen (`Liste.forin`, `Obj.notnil`, `Obj.free`)
- **Schnellbefehle** nach Enter, etwa `/uses Unit`, `/extract`, `/inline`, `/fix`, `/explain`, `/case`, `/helper`, `/test`, `/component`, `/unit`, `/sortuses`, `/cleanuses`
- **Erzeugen-Menü** (Alt+Einfg): Konstruktor, Properties, überschriebene Methoden, Interface-Methoden, Umschließen, Vorlagen
- **Freigabe absichern:** nach `X := TFoo.Create;` ein Angebot für `try … finally X.Free; end;`
- **Schreibhilfen im Editor**: Gleichen Text wie die Markierung hervorheben (#709), Blockkommentar umschalten (#703, Umschalt+Alt+A), neue Zeile ober- oder unterhalb (#700, Umschalt+Enter, Strg+Alt+Enter), Markierung beim Tippen umschließen (#672), Umschließung entfernen (#657, Strg+Umschalt+Entf) mit Vorschau, Atlas-Spalte in der Zeilenleiste (#768)
- **Bedingte Kompilierung**: Gliederung, Hover, Gehe zu und Prüfungen sehen nur die aktiven `{$IFDEF}`-Zweige des Projekts, die Gliederung zeigt die Bedingung des Zweigs (#845); `{$IF}` versteht `SizeOf`, `High`, `Low`, `RTLVersion111` und `Declared`, `{$IFOPT}` folgt den Schaltern der `.dproj` und lokalen `{$R-}`, unbekannte Werte lassen beide Zweige aktiv, und der Hover auf einer Bedingung erklärt ihren Wert (#847)
- **Variante Records**: Felder wie `TRect.Left` oder `TMessage.WParam` stehen in Vervollständigung, Hover, Gehe zu und Gliederung, mit ihrem Zweig als Marke (#846)
- **Helfer mit Vorfahr**: `class helper (TBaseHelper) for TFoo` wird als Helfer gelesen, und `Foo.` bietet auch die Mitglieder des Vorfahr-Helfers an (#848)
- **Seltenere Syntax**: mehrere Einschränkungen je Typparameter, benannte OLE-Argumente (`Open(FileName := 'a.docx')`), Aufrufkonventionen ohne Semikolon, `cdecl varargs`, `assembler asm`, lokale Routinen in anonymen Methoden, `{$I datei.inc}` als Wert einer Konstanten, lange `else if`-Ketten, Sprungmarken wie `@@End` in `asm`-Blöcken (#861), Steuerzeichen wie `^C` und die Klammern `(.` `.)` (#862, mit Inlay Hint für den Code) ergeben keine Syntaxfehler; unter `{$SCOPEDENUMS ON}` brauchen Werte ihr Typpräfix, Mitglieder aus `{$I}` in einer Klasse gehören zur Klasse (#849)
- **Defines aus Include-Dateien**: ein `{$DEFINE}` aus einer per `{$I}` eingebundenen Datei gilt für Abblenden, Gliederung, Prüfungen und Linter; ein Inlay Hint hinter `{$I}` nennt die Symbole, die die Datei definiert (#860)
- **Dokumentationskommentare:** `///` erzeugt das XMLDoc-Gerüst mit Platzhaltern
- **Anweisung vervollständigen** (Strg+Umschalt+Enter), **Muster fortsetzen** als Schattentext, **Kommentare fortsetzen** beim Enter
- **Formatieren** nach eigenen Regeln (Strg+Umschalt+Alt+L), weil RAD Studio 13 keinen Formatierer mehr hat
- **Zeilen verschieben und duplizieren** (Alt+↑/↓, Umschalt+Alt+↑/↓), **mehrere Einfügemarken** *(experimentell)*, **Bezeichner live mitziehen** *(experimentell)*, **Einfügen mit uses-Ergänzung** *(experimentell)*

### Verstehen

- **Hover-Tooltip** im Atlas-Stil statt Help Insight: Deklaration, XMLDoc in auf- und zuklappbaren Abschnitten, anklickbare Typen, Vererbungskette, Werte von Konstanten, Mengen und Resourcestrings, published-Mitglieder von Komponenten als Tabelle, Symbole in `{$IFDEF}` mit ihrer Herkunft, Aktionen (Gehe zu, Verwendungen, Deklaration kopieren, Hilfe)
- **Werte beim Debuggen:** Ist der Prozess angehalten, zeigt der Tooltip den Wert des Ausdrucks unter der Maus, ausgewertet über den Debugger der IDE ohne Nebenwirkungen
- **Typmarken** hinter `var X := …` ohne Typangabe
- **Code-Metriken** als Marke hinter jedem Methodenkopf (Länge, Tiefe, zyklomatische und kognitive Komplexität, Parameter, Operanden der größten Bedingung, lokale Variablen, Ausstiege), hinter jeder Klasse (Member, Vererbungstiefe ohne RTL und VCL), dem Unit-Namen (Zeilen) und dem ersten `uses` (Units)
- **Rekursion im Rand**, **inaktive `{$IFDEF}`-Zweige** abgeschwächt mit Grund im Tooltip, **ungenutzte uses** abgeblendet
- **Klammer- und Blockpaare** farbig nach Tiefe, mit eigenen Blocklinien

### Navigieren

- **Gehe zu** Definition (Strg+Klick), Implementierung und Typdefinition; Wechsel zwischen Deklaration und Implementierung (Strg+Umschalt+↑/↓); **Sprung zum Gegenstück** (begin ⇄ end, try → finally → end, `{$IFDEF}` → `{$ENDIF}`)
- **Brotkrumenleiste** über dem Editor mit Sprungmenüs zu Unit, Klasse, Methode und deren Kindern
- **Editorleiste** mit Symbolen: Sprung zum interface- bzw. implementation-Teil (und zurück mit „↩ 214“), Methode suchen, Navigationsverlauf und beliebige Palettenbefehle; Überlaufmenü, frei belegbar, auch rechts in der Brotkrumenzeile
- **Gliederung** als andockbares Fenster mit Filter
- **Definition einblenden** (Alt+F12) unter der Zeile, ohne die Datei zu wechseln
- **Datei und Symbol schnell öffnen** (Strg+P) über Projekt, Projektgruppe und Suchpfad; projektweite **Symbolsuche**
- **Units suchen** (Strg+F12) im eigenen Fenster mit Vorschau, Gruppen, Filtern und „In uses aufnehmen“
- **Ergebnisfenster** „Atlas-Ergebnisse“ für Referenzen (auch in Formularen), Implementierungen, Aufrufer, Aufrufe und Vererbung
- **Navigationsverlauf** über Dateien hinweg
- **Benannte Lesezeichen** (Strg+Alt+K) und persönliche **Notizen** an Codezeilen, die nicht im Quelltext landen
- **Schnelle Lesezeichen** in einer Spalte links der Zeilennummern: Klick setzt und entfernt, Strg+Umschalt+1…9 nummeriert, Strg+1…9 springt projektweit, Strg+Umschalt+K unnummeriert (die Faltungsakkorde der IDE bleiben), wandern mit dem Code mit und übernehmen die IDE-Lesezeichen
- **Übersichtsleiste** an der Scrollleiste mit Fehlern, Treffern und Änderungen; **Minimap** *(experimentell)*; **mitlaufender Kopf** der umgebenden Klasse und Routine *(experimentell)*
- **TODO-Übersicht** des Projekts aus `// TODO`, `// FIXME` und dem To-do-Format der IDE

### Code-Analyse

Der Server prüft jede Unit beim Tippen. Treffer erscheinen als Wellenlinien, im Tooltip, gekürzt am Zeilenende und projektweit im andockbaren Fenster **„Atlas-Prüfung“** (Strg+Alt+P); die Markierungen wandern beim Tippen mit.

- **Fenster „Atlas-Prüfung“:** Befunde der Datei, des Projekts oder der Projektgruppe live, Filter je Art, Kategorie und Text, Gruppierung nach Datei, Regel oder Kategorie, sortierbare Spalten; Enter springt, Alt+Enter korrigiert, Kontextmenü zum Unterdrücken, Einstellen, Abschalten und Erklären der Regel. „Offene zuerst“: Die Unit im Editor steht angepinnt oben, darunter die übrigen geöffneten Units, nicht geöffnete folgen ausgegraut (oder normal bzw. ausgeblendet); auf Wunsch auch die aktive Unit ohne Befunde („Keine Befunde“)
- **Befund-Hover** mit Schweregrad, Regel und Aktionszeile „Alt+Enter: Korrektur“, „Für diese Zeile unterdrücken“, „Regel einstellen…“
- **Seite „Prüfregeln“** in den Optionen: je Regelgruppe ein Hauptschalter und eine Tabelle mit Schweregrad, Ausnahmen und Optionen jeder Regel, Suche und Katalogtext mit Beispielen

- **279 Prüfregeln** in vier Kategorien: 185 Fehler, 84 Code-Smells, 5 Schwachstellen, 5 Sicherheits-Hotspots. Darunter:
  - **Korrektheit:** nicht gesetztes `Result`, möglicherweise uneingeleitete Variablen, unerreichbarer Code, ungenutzte Variablen, Parameter und Zuweisungen, deklarierte, aber nicht implementierte Methoden, fehlendes `override`, verdeckte virtuelle Methoden, Überläufe, Gleitkomma-Vergleiche, `raise` in `finally`, übersehener Vorrang von `not` (`not X in Menge`), leere Anweisung nach `then`/`do`/`else`, Schleifen einen Schritt zu weit (`0 to Liste.Count`), Listen in der eigenen Schleife verändert (`Delete` in einer Vorwärtsschleife), Objekte nach `Free` weiter benutzt (mit Sprung zur Freigabe), Zugriff vor der nil-Prüfung (`X.Name` vor `if Assigned(X)`), Felder außerhalb des Destruktors ohne `nil` freigegeben, im Konstruktor erzeugte Felder, die der Destruktor nie freigibt, Destruktoren, die ein Feld benutzen, das nach einer Exception im Konstruktor noch nil ist (`FZeilen.Clear`, wenn vorher `TFileStream.Create` warf; Korrektur `if Assigned`), Windows-Handles aus `CreateFile`, `FindFirstFile`, `RegOpenKeyEx`, `LoadLibrary`, `GetDC` oder GDI-Objekte, die nicht auf jedem Weg geschlossen werden (Korrektur `try … finally CloseHandle`), in `initialization` oder einem `class constructor` erzeugte Objekte, die `finalization` bzw. der `class destructor` nie freigibt, Konstruktoren und Destruktoren ohne `inherited`, `Destroy` statt `Free`, `FillChar`/`Move`/`GetMem` auf Records mit Strings oder Interfaces, `PChar` auf temporäre Strings, `out`-Parameter, die vor dem Setzen gelesen werden, `Find` auf unsortierten `TStringList`s, `DelimitedText` ohne `StrictDelimiter`, Änderungen an der globalen `FormatSettings`, die die ganze Anwendung und alle Threads treffen (Korrektur: lokale `TFormatSettings`), `Writeln` in Programmen ohne Konsole, `raise` im Destruktor, doppelte Bedingungen und gleiche Zweige, `case` über Aufzählungen, denen Werte fehlen, `DisableControls`/`BeginUpdate`/`Screen.Cursor` ohne `try`/`finally`, `StrToInt` auf `Edit.Text` ohne Prüfung, Zahlen aus Datenbank, Registry oder Text ohne Bereichsprüfung in eine Aufzählung umgewandelt (Korrektur mit `InRange`), `CreateProcess` mit unveränderlicher Befehlszeile wie `PChar('notepad.exe')` (Korrektur mit Kopie und `UniqueString`), Zugriff in `OnCreate` auf ein Formular, das die `.dpr` erst später erzeugt, `on E: Exception` vor einem spezielleren Handler, der so nie erreicht wird (die Korrektur zieht ihn nach vorn), `raise E;` im Handler, das die ursprüngliche Absprungstelle verliert (Korrektur `raise;`), `Dict[Key]` ohne `ContainsKey` oder `TryGetValue`, `Copy(S, 0, N)` und `Pos(…) > -1` (Strings zählen ab 1), Ereignisse wie `FOnChange(Self)` ohne `Assigned` aufgerufen (die Korrektur ergänzt die Prüfung), von Hand freigegebene Elemente einer besitzenden `TObjectList` (doppelte Freigabe), `TStringList.Create;` ohne Zuweisung (die Korrektur legt eine Variable mit `try`/`finally` an), `Self` als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann (eigene Referenzzählung im Konstruktor, `TInterfacedObject` nach `inherited AfterConstruction`; die Korrektur verschiebt den Aufruf vor `inherited`), Formulare und andere Komponenten, die als Interface gespeichert (`Bus.Anmelden(FAnsicht as IBeobachter)`) und dann ohne Abmeldung freigegeben werden (die Korrektur fügt die Abmeldung vor `Free` ein), Vergleiche mit `Null`, deren Ergebnis von `NullEqualityRule` abhängt (Korrektur `Feld.IsNull` bzw. `VarIsNull`), Speicher aus `GetMem` oder `New`, der nie freigegeben wird (die Korrektur ergänzt `try … finally FreeMem`), Objekte, die `AddObject` in eine `TStringList` ohne Besitz legt (die Korrektur setzt `TStringList.Create(True)`), dasselbe Feld oder dieselbe Property zweimal hintereinander gesetzt (`Panel.Left` doppelt statt `Left`/`Top`), Bedingungen, die immer wahr oder falsch sind (`if (Anzahl > 0) or True`, `if DEBUG_MODUS then` mit einer Konstanten; die Korrektur entfernt den toten Zweig), Schleifen ohne Ausgang (`while True do` ohne `Break`, `Exit` oder `raise`), Schleifenbedingungen, die sich im Rumpf nie ändern (`while I < Liste.Count` ohne `Inc(I)`), Rekursion ohne Abbruch (eine Routine, die sich auf jedem Pfad selbst aufruft), vertauschte Argumente von Pos, StartsText oder ContainsText, Ganzzahldivision an eine Gleitkommazahl, Strings, dynamische Arrays, Interfaces und Typparameter im varianten Teil eines Records oder hinter `file of` (die Korrektur verschiebt das Feld vor `case`), Interface-GUIDs, die nicht die Form `{8-4-4-4-12}` haben (die Korrektur erzeugt eine neue), Interfaces und Strings, die über `Pointer(FIntf) := …` an der Referenzzählung vorbei zugewiesen werden (Korrektur `[weak]` bzw. `[unsafe]`), statische Arrays und Records ab 2 GB, aus den Deklarationen berechnet
  - **Threads:** VCL-Zugriff aus Threads, Sperren ohne `finally`, `FreeOnTerminate`-Fallen, `Synchronize` im Destruktor, `threadvar` mit Strings, `Application.ProcessMessages` in Schleifen und Ereignis-Handlern, `TThread.Queue(nil, …)` in Packages (Korrektur auf den eigenen Wrapper), `Sleep`/`WaitFor` in Formularen und Ereignis-Handlern, die die Oberfläche einfrieren, Schleifen in `Execute`, die `Terminated` nie prüfen (die Korrektur ergänzt es), `CreateAnonymousThread` ohne `Start` (die Korrektur hängt es an), `TTask.Run` ohne `try … except`, dessen Exceptions verloren gehen (die Korrektur schließt den Rumpf ein), Variablen und Sammlungen von außerhalb, die `TParallel.For` oder in einer Schleife gestartete Tasks ohne Sperre schreiben (die Korrektur nimmt `TInterlocked` bzw. eine `TMonitor`-Sperre), Zähler, die `Execute`, `TTask.Run` oder anonyme Threads ohne Sperre mit `Inc` erhöhen (die Korrektur nimmt `TInterlocked.Increment`)
  - **Datenbank:** `while not Q.Eof`-Schleifen ohne `Q.Next` auf jedem Weg (die Korrektur fügt es ein), `Edit`/`Append` ohne `Post` oder `Cancel` (Korrektur mit `try … except Cancel`), Transaktionen ohne `Rollback` bei Exceptions (FireDAC, IBX, dbExpress, ADO; Korrektur mit `try … except Rollback`), `UPDATE`/`DELETE` ohne `WHERE` im Code, in Konstanten und in der Formulardatei (Option `allowTables` für absichtlich geleerte Tabellen), `SELECT *` (standardmäßig aus; die Korrektur setzt die persistenten Felder der Datenmenge ein)
  - **Compiler vorab:** Compilerfehler schon beim Tippen, ohne Build: Methodenköpfe der Implementierung, die von der Deklaration abweichen (Parameter, `const`/`var`, Ergebnistyp, Aufrufkonvention; wie E2037, die Korrektur gleicht eine der beiden Seiten an), Interface-Methoden, die in der Klasse fehlen (wie E2291, auch mit abweichendem Kopf oder einer Zuordnung für ein nicht genanntes Interface; die Korrektur deklariert und implementiert sie), Units in `uses`, die der Compiler weder im Projekt noch in Such- und Bibliothekspfaden findet (auch als `.dcu`; wie F2613, mit ähnlichen Namen, Korrekturen für das Namespace-Präfix oder einen fehlenden Suchpfad in der `.dproj`), fehlende Dateien aus `in '…'`, Packages aus `requires` und Units, die sich selbst einbinden, Attribute wie `[TestFixture]`, die Delphi still übergeht, weil ihre Unit fehlt (wie W1074; die Korrektur ergänzt die Unit), Vergleiche wie `Result = 0;` als eigene Anweisung (wie E2014; die Korrektur ersetzt `=` durch `:=`), doppelte `case`-Marken, auch über Bereiche und Konstanten mit gleichem Wert und in varianten Records (wie E2030, E2027; die Korrektur entfernt den späteren Wert), Felder nach Methoden oder Properties im selben Abschnitt, die FPC übersetzt, Delphi aber nicht (wie E2169; die Korrekturen verschieben das Feld nach oben oder setzen `var` davor), Überladungen ohne `overload` oder mit gleichen Parametern (wie E2254, E2267, E2252, E2301; die Korrektur hängt überall `overload;` an), doppelt deklarierte Bezeichner im selben Bereich und doppelte Units in `uses` (wie E2004; die Korrektur entfernt die zweite), offene oder überzählige bedingte Direktiven, fehlende Symbole, unbekannte Direktiven und `{$WARN}`-Bezeichner, unpaarige `{$PUSHOPT}`/`{$POPOPT}` und ungültige Werte für `{$ALIGN}` (wie E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573; die Korrekturen ergänzen `{$ENDIF}`, entfernen eine überzählige Direktive oder korrigieren den Tippfehler), `override` ohne passende virtuelle Methode im Vorfahren, auf eine statische oder `final`-Methode und Klassen, die von einer `sealed`-Klasse ableiten (wie E2137, E2170, E2352, E2353; die Korrektur übernimmt die Signatur des Vorfahren in Deklaration und Implementierung, auch bei Tippfehlern wie `Destory`), `Create` auf einer Klasse mit nicht überschriebenen abstrakten Methoden oder einer `abstract`-Klasse (wie W1020, E2402; die Meldung nennt die offenen Methoden, die Korrektur überschreibt sie in einer Klasse der Datei), Getter, Setter und Felder hinter `read`/`write`, die fehlen, überladen sind, eine falsche Signatur oder einen `var`-Parameter haben, Klassen- und Instanzmitglieder mischen oder ungültige Feldselektoren nutzen (wie E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562; die Korrektur legt ein fehlendes `FName`, `GetName` oder `SetName` an), Zuweisungen an ein Feld eines Records, den eine Property, Default-Property oder Funktion nur als Kopie liefert, und an Konstanten (wie E2064; die Korrektur weist über eine lokale Variable zu und schreibt zurück), Zuweisungen an Properties ohne `write` und Lesen von Properties ohne `read` (wie E2129, E2130; die Korrekturen rufen `Clear` statt `Count := 0` auf, weisen das Feld hinter `read` zu oder legen den Setter an), Aufrufe mit zu vielen oder zu wenigen Argumenten für eine Routine ohne Überladung (wie E2034, E2035; die Korrektur öffnet den Parameter-Hint in den Klammern). Meldet der nächste Build denselben Fehler an derselben Zeile, zeigt Atlas nur einen Eintrag mit der Marke „Atlas + dcc“ und „vom Compiler bestätigt (E2035)“ (Einstellung „Bestätigte Compilermeldungen“: zusammenführen oder beide zeigen); die Spalte „Compiler“ im Fenster „Atlas-Prüfung“ nennt den Code. Unter Prüfregeln › Compiler vorab schalten der Hauptschalter alle Regeln der Gruppe und „Regeln der Stufe T prüfen“ nur die ab, die Ausdruckstypen brauchen; der Compilercode in Meldung, Spalte und Hover lässt sich ausblenden, `Break` und `Continue` außerhalb einer Schleife sowie `Break`, `Continue` und `Exit`, die einen `finally`-Block verlassen (wie E2097, E2126; die Korrektur ersetzt `Break` durch `Exit`), `raise;` ohne Argument außerhalb eines `except`-Blocks, etwa in einer lokalen Prozedur, die aus dem Handler gerufen wird (wie E2145), falsch verwendete Sprungmarken: doppelt gesetzt, nie gesetzt, nicht deklariert oder mit `goto` in einen `try`-Block hinein bzw. aus ihm heraus (wie E2073, E2074, E2093, E2127), Schleifenvariablen, die im Rumpf zugewiesen, mit `Inc`/`Dec` verändert oder als `var`-Parameter übergeben werden oder keine einfache lokale Variable sind (wie E2081, W1015, E1019; die Korrekturen stellen auf `while` um bzw. verwenden `for var`), Schleifenvariablen, die nach dem normalen Ende der Schleife gelesen werden (wie W1037, Korrektur nach `while`), Zählschleifen mit `to`, die nie laufen (`High … to Low`, konstante Grenzen wie `10 to 1`; wie H2135, Korrektur `downto`), `inherited Name(…)` auf eine im Vorfahren abstrakte Methode (wie E2373; die Korrektur entfernt den Aufruf), Typargumente, die die Einschränkung ihres Typparameters verletzen (`class`, `record`, `constructor`, Interface oder Basisklasse), `T.Create` ohne `constructor`-Einschränkung und Methodenaufrufe auf Werten eines unbeschränkten `T` (wie E2511–E2515, E2568, E2571; die Korrektur ergänzt die Einschränkung), unbekannte Typnamen in Deklarationen, Typumwandlungen und Zeigerzielen sowie Namen, die kein Typ sind (wie E2003, E2005, E2564; die Korrektur ergänzt die deklarierende Unit in uses), `Create` über eine Klassenreferenz (`class of TBasis`), deren Konstruktor nicht virtuell ist, sodass immer der Konstruktor der Basisklasse läuft (wie E2391; die Korrektur ergänzt `virtual` und `override` in den Nachfahren), `New`, `Dispose` und `SetLength` ohne Länge auf dynamischen Arrays (wie E2255, E2256, E2246, E2307, E2308; Korrekturen `A := nil` und `SetLength(A, 1)`), lokale (verschachtelte) Routinen als Prozedurvariable oder Argument eines prozeduralen Typs (wie E2094, E2278; die Korrektur verschiebt die Routine auf Unit-Ebene), Integer und HRESULT zwischen Interface-Methode und Implementierung vertauscht (wie X1008; die Korrektur gleicht den Ergebnistyp an), ungültige Argumente für var- und out-Parameter: String-Elemente, Konstanten, Properties, Funktionsergebnisse, Slice und Ausdrücke (wie E2354, E2197, E2192, E2454, E2036; die Korrektur übergibt eine lokale Variable), Bedingungen in if, while und until, die kein Boolean sind (wie E2012; die Korrektur ergänzt <> 0, > 0, <> nil bzw. Assigned), for-in über Typen ohne Enumerator (wie E2430, E2431), Fehler in konstanten Ausdrücken: Division durch null, Überlauf, Bereiche wie `array[5..1]`, Werte außerhalb des Typs und zu große Hex-Literale (wie E2098, E2099, E2011, W1012, E2102), unzulässige Standardwerte von Parametern (mehrere Namen mit einem Standardwert, Parameter ohne Standardwert nach einem mit, `var`/`out`, Records und große Mengen; wie E2237, E2238, E2239, E2268, E2146; die Korrekturen deklarieren die Namen einzeln bzw. verschieben die Parameter mit Standardwert ans Ende), vorzeichenbehaftete und vorzeichenlose Operanden in Vergleichen oder Rechnungen gemischt (Integer mit Cardinal, alles mit UInt64; wie W1023, W1024, W1073; die Korrektur wandelt den vorzeichenlosen Operanden in Int64 um), Zuweisungen mit möglichem Datenverlust, standardmäßig aus (Int64 oder NativeInt an Integer, einstellbare Paare wie Double>Single; wie W1071, W1072, W1066; die Korrekturen wandeln ausdrücklich um oder vergrößern den Zieltyp), typisierte Konstanten, die per Zuweisung oder als var-Argument verändert werden (wie W1016, W1017; mit {$J-} wie E2064, E2197), und 0 statt nil bei Zeigerkonstanten (wie W1013); die Korrekturen machen aus der Konstante eine initialisierte Variable bzw. schreiben nil, überschrittene String-Grenzen: Literale, die an `string[N]`/ShortString gekürzt werden (wie W1014), Literale über 255 Zeichen vor Delphi 12 (wie E2056) und resourcestrings über 4096 Zeichen (wie E2381); die Korrekturen deklarieren das Ziel als string bzw. teilen das Literal
  - **Ausnahmen:** leere `except`-Blöcke, Auffangen ohne erneutes `raise`, erzeugte, aber nicht ausgelöste Ausnahmen, leere `finally`-Blöcke, Konstruktoren, die `try` vor `inherited Create` betreten (die Korrektur zieht den Aufruf vor `try`)
  - **Komponenten und Formulare:** fehlendes `inherited`, `Notification`, falsche `default`-Werte, Felder ohne Objekt im Formular und umgekehrt, Datenbindungen und Datenquellen in DFM-Dateien, Message-Handler (`message WM_SIZE`) ohne `inherited`, IDE-Notifier ohne `RemoveNotifier` (die Korrektur merkt den Index und meldet beim Entladen ab), DUnitX-Tests ohne Prüfung, `inherited` an der falschen Stelle (im Destruktor vor dem Freigeben eigener Felder, im Konstruktor nach dem Zugriff auf geerbte Properties; die Korrektur verschiebt es), `inherited Laden` im überschriebenen `Speichern` (die Korrektur setzt den eigenen Namen, Option `allowed`), Getter, die den Zustand ihres Objekts ändern (`Inc(FAbrufe)` in `GetWert`, Lazy-Initialisierung erlaubt), `Equals` ohne `GetHashCode` überschrieben (Korrektur mit `THashBobJenkins`) und Records mit `class operator Equal` als Dictionary-Schlüssel ohne Comparer, Formular-Units ohne `{$R *.dfm}` (die Korrektur fügt es ein) und `{$R}` auf eine fehlende Formulardatei, Formulare, die `Application.CreateForm` und zusätzlich der Code erzeugt (die Korrektur entfernt die Zeile aus der `.dpr`), Handler in geerbten Formularen, die den Handler des Vorfahren nicht mehr aufrufen (die Korrektur fügt `inherited;` ein), Formulare, die sich im eigenen Ereignis-Handler freigeben (die Korrektur nimmt `Release` bzw. `Action := caFree`)
  - **Laufzeitumgebung:** Dialoge (`ShowMessage`, `MessageDlg`, `InputBox`) in Konsolenprogrammen, Windows-Diensten und DLLs ohne Formulare, `LoadFromFile`/`SaveToFile` und `TFile.ReadAllText` ohne Kodierung (Korrektur `TEncoding.UTF8`), Schreiben nach `HKEY_LOCAL_MACHINE` (Korrektur `HKEY_CURRENT_USER`), Laufzeiten mit `Now` gemessen (Korrektur `TStopwatch`)
  - **Dateien und Systemnähe:** Pfade ohne Trennzeichen zusammengesetzt (`TPath.GetDocumentsPath + 'export.csv'`, Korrektur `TPath.Combine`), feste Laufwerks-, Benutzer- und Netzwerkpfade (Option `allowUnits`), Dateinamen mit `=` statt `SameFileName` verglichen, DLL-Exporte ohne Aufrufkonvention oder mit Strings, dynamischen Arrays, Objekten oder Interfaces ohne GUID (Korrektur `stdcall`, Option `allowShareMem`)
  - **Sicherheit:** SQL- und Befehlsinjektion, Pfadmanipulation, schwache Kryptografie, abgeschaltete TLS-Prüfung, unsicheres HTTP und Zufall, Trojan Source (Bidi-Steuerzeichen, unsichtbare und verwechselbare Zeichen)
  - **Architektur und Stil:** verbotene uses, Importregeln nach Rollen, bis zum Ende der Unit abgeschaltete Compiler-Warnungen, Hinweise, Bereichs- oder Überlaufprüfungen (Option `allow`), `with`, überflüssige Klammern und `begin … end`, Bedingungen und Schleifen ohne `begin … end` (Korrektur für die Anweisung, die Methode oder die Datei; schaltet die Regel für überflüssiges `begin … end` stumm), Dateikopf, hartkodierte Texte, Metrik-Grenzwerte (auch Member je Klasse, Zeilen je Unit, Units im uses), öffentliche Felder (freiwillig, die Korrektur kapselt sie), globale Variablen im interface (freiwillig), lokale Namen, die ein Feld oder eine Property verdecken, `if`, das nur `True` oder `False` zuweist, `UpperCase(A) = UpperCase(B)` statt `SameText`, Zahlen ohne Namen, zu lange Zeilen (freiwillig; über 1023 Zeichen immer ein Fehler wie F2069) und auskommentierter Code (die Korrektur entfernt ihn), Geldbeträge als `Double` statt `Currency` (freiwillig), lange `if`-Ketten über denselben String (freiwillig, Korrektur `case IndexStr`), public- und published-Methoden, -Konstanten und -Properties, die kein Projekt der Projektgruppe verwendet (projektweit über den Symbolindex; still bei Packages und Bibliotheken, während der Index lädt und bei RTTI, Interfaces und Formularbindungen), ungenerische `TList`/`TObjectList`, die mit Cast gelesen werden, statt `TList<T>` (freiwillig; die Korrektur stellt die Liste auf `TList<T>` um), ebenso `TStack`/`TQueue`/`TObjectStack`/`TObjectQueue` aus Contnrs (freiwillig; die Korrektur stellt auf `TStack<T>` usw. um, Warteschlangen mit `Enqueue`/`Dequeue`, Objektstapel mit `Create(False)`, damit die Besitzregel gleich bleibt)
  - **Performance:** `SetLength(A, Length(A) + 1)` in Schleifen (bei bekannter Anzahl setzt die Korrektur die Länge vor der Schleife), String-, Interface-, Array- und Record-Parameter ohne `const`, die die Routine nie verändert (optional; die Korrektur ergänzt `const` in Deklaration und Rumpf)
- **Konfidenz** (hoch, mittel, niedrig) je Treffer begrenzt den Schweregrad; **Profile** `standard`, `fast`, `strict`, `security`, `style` oder eigene in `atlas.json`
- **Unterdrücken** mit `// lsp-ignore: regel`, mit Meldung unbenutzter oder vertippter Unterdrückungen
- **Baseline** für Altprojekte: bekannte Treffer ausblenden, nur neue melden
- **Compilerprüfung nach dem Speichern** und Übernahme der Meldungen aus dem Reiter „Build“
- **Suchpfade und Defines prüfen** für das aktive Projekt (Karte auf der Atlas-Willkommensseite)
- **Linter ohne IDE:** `AtlasServer.exe --check` für Pre-Commit-Hooks und CI, als Text, JSON oder SARIF für GitHub Code Scanning, auf Wunsch nur geänderte Dateien oder Zeilen (siehe [Linter-Modus](#linter-modus))

Jede Regel mit Beschreibung und Vorher-Nachher-Beispiel: [docs/Regeln.md](docs/Regeln.md).

### Refactorings und Code-Aktionen

Code-Aktionen öffnet Alt+Enter; alles steht auch im Menü *Atlas* und im Kontextmenü des Editors.

- **Umbenennen** projektweit mit Vorschau, samt `.dfm`/`.fmx` und automatisch benannter Ereignis-Handler
- **Signatur ändern** im Dialog: Parameter hinzufügen, entfernen, verschieben, umbenennen, mit Vorschau
- **Methode extrahieren**, **Variable einführen**, **Bedingung in Funktion auslagern**, **with auflösen**, **case ergänzen**
- **Variable und Methode einbetten** *(experimentell)*, **Klasse in eigene Unit verschieben** *(experimentell)*, **uses nachziehen nach dem Umbenennen einer Unit** *(experimentell)*
- **Klassen-Aktionen:** Interface implementieren, Methoden überschreiben, Getter, Setter und Feld erzeugen, Property aus vorhandenen Zugriffsmethoden, Methode aus einem Aufruf anlegen, Forward-Deklaration ergänzen
- **Texte:** String als `resourcestring` auslagern
- **uses:** fehlende Unit ergänzen, sortieren, ungenutzte entfernen
- **Schnellkorrekturen** zu vielen Prüfregeln, auch „Alle korrigieren“
- **Atlas-Änderungen zurücknehmen** (Strg+Alt+Z): Änderungen über mehrere Dateien als ein Schritt

### Formulare

- Offene Formulare gehen im Stand des Designers an den Server: Referenzen, Umbenennen und Prüfungen sehen auch ungespeicherte Komponenten
- Umbenennen eines Ereignis-Handlers ändert auch seine Zuordnung im Designer
- Komponenten des Formulars in der Vervollständigung, `Sender` mit passender Typumwandlung
- Prüfungen zwischen Formular und Code sowie **Eigenschaftsregeln** für Formulardateien mit Schnellkorrektur
- Binäre Formulare in Textformulare umwandeln

### Bauen, Testen, Debuggen

- **Release-Build-Wächter:** prüft vor einem Release-Build die Projektoptionen (DEBUG-Symbol, Debug-Informationen, …)
- **DUnitX-Tests** aus dem Editor ausführen und einen einzelnen Test im Debugger starten (Code Lens an `[Test]` und `[TestFixture]`)
- **Startprofile** für Parameter, Arbeitsordner, Umgebung und Host-Anwendung
- **Werte im Hover beim Debuggen** (siehe [Verstehen](#verstehen))
- **Bauen-Werkzeug für Claude Code:** `build_project` baut offene Projekte über den Compiler der IDE, auch in der Starter-Edition

### IDE-Komfort

- **Atlas-Willkommensseite** im andockbaren Fenster *Atlas-Start* (*Ansicht › Atlas-Start*, Befehlspalette; mit `welcomePage.openOnStart` beim Start der IDE; die Willkommensseite der IDE bleibt unberührt) mit Bereichen: Weiterarbeiten, Projekte mit Schnellaktionen, Projektverlauf, Nicht gesichert, Projekt einrichten, Testergebnisse, Meine Issues, Neu in Atlas, Atlas entdecken, Hilfe und Rückmeldung; Suchfeld und freies Layout
- **Befehlspalette** (Strg+Umschalt+P) für alle Atlas-Befehle
- **Atlas-Statusfeld** mit Indexfortschritt und Schnellschaltern (Strg+Umschalt+Alt+A)
- **Benachrichtigungszentrale** (Strg+Umschalt+Alt+N) sammelt Hinweise von Builds, Prüfungen und Server
- **Änderungsmarken** in der Rinne gegenüber Git HEAD bzw. SVN BASE
- **Markierung suchen** mit F3 bzw. Umschalt+F3
- **Stilles Neuladen** extern geänderter Dateien
- **Robustheit:** kein Fehler in Atlas erreicht die IDE, Hänger-Wächter mit Protokoll, Stacktraces mit Unit und Zeile für jeden abgefangenen Fehler, Prüfregeln und Editorfunktionen vertragen beliebig tief verschachtelte Ausdrücke ohne Rekursion (eine Unit jenseits des Netzes von 100000 Ebenen bekommt den Hinweis `unit-too-deep`, statt still ihre Befunde zu verlieren), eine wiederholt fehlerhafte Funktion wird einzeln abgeschaltet (mit Benachrichtigung zum Wiedereinschalten), die übrigen laufen weiter, Serverabstürze stehen mit Ursache (Exit-Code, stderr) im Protokoll, und ein Server, der zweimal gleich abstürzt, wird nicht in einer Schleife neu gestartet, abgesicherter Start nach einem Absturz (ein langsamer Start ist keiner: Statt beim nächsten Start Funktionen abzuschalten, nennt Atlas, wie lange es den Start aufgehalten hat und welche seiner Teile am längsten brauchten), eigene Datendateien (Favoriten, Verläufe, Lesezeichen, Notizen …) werden in einem Schritt ersetzt, eine beschädigte liegt danach als `.defekt` daneben statt still überschrieben zu werden, Fehlerbericht zum Anhängen, Tastenkonflikte mit anderen Erweiterungen (GExperts, CnPack, MMX) werden erkannt
- **Update-Prüfung** nur nach Zustimmung
- **Barrierefreiheit:** Listen und Tooltips für UI Automation lesbar

### Einstellungen

- *Tools › Optionen › Drittanbieter › Atlas* als Baum: Bereiche oben, jede Funktion mit eigenem Hauptschalter, der ihre Unteroptionen mit abschaltet; daneben die Seiten *Snippets*, *Tastenkonflikte* und *Server*
- Jede sichtbare Funktion lässt sich einzeln abschalten; experimentelle Funktionen sind gekennzeichnet
- Einstellungen exportieren, importieren, Profile laden und zurücksetzen
- Teamweite Werte in der Projektdatei `.atlas`, Server- und Regeleinstellungen in `atlas.json` (*Atlas › Projekt-Einstellungen*), globale Werte in `%APPDATA%\Atlas\settings.json`

Alle Schlüssel: [docs/Einstellungen.md](docs/Einstellungen.md) und [docs/Konfiguration.md](docs/Konfiguration.md).

### Claude Code und MCP

Der Server bietet Claude Code 19 MCP-Werkzeuge: Symbole suchen, Deklarationen und Typ- und Aufrufhierarchien lesen, Komponenten- und Formularinfos, Diagnosen, Metriken und TODOs abfragen, geplanten Code mit `check_code` vor dem Schreiben prüfen, Treffer erklären, über die IDE bauen (`build_project`, `get_last_build`), DUnitX-Tests ausführen und schreibend umbenennen oder Code-Aktionen anwenden (mit Vorschau). Dazu die Ressource `delphi://conventions` mit den Konventionen des Projekts. Einrichtung: [Editors/ClaudeCode](Editors/ClaudeCode/README.md), Werkzeuge: [docs/MCP.md](docs/MCP.md).

### Geplant

Noch nicht in `main`, als Issues angelegt:

- Über 100 weitere Prüfregeln (Unter-Issues von #909, #1086)
- Compilermeldungen als eigene Atlas-Regeln, schon beim Tippen statt erst beim Übersetzen (#1024)

## Installation

### IDE-Plugin für RAD Studio 13 und 12

1. Repository klonen und `Atlas.groupproj` in RAD Studio öffnen.
2. `Atlas.Text`, `Atlas.Common`, `Atlas.Windows` und `AtlasServer` für **Win64** erzeugen (alle vier für dieselbe Plattform). Ergebnis: `Output\Win64\Debug\Bin\AtlasServer.exe`. Alternativ `AtlasServer.exe` aus einem [Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) nehmen; der Server hängt nicht von der Delphi-Version ab.
3. `Atlas.IDE.Expert` mit der Delphi-Version erzeugen, in der das Plugin laufen soll: für die klassische IDE **Win32**, für die 64-Bit-IDE **Win64**. Ergebnis: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl` (Delphi 13; Delphi 12: `…290.bpl`, 64-Bit-IDE: `Output\Win64\…`).
4. *Komponente › Packages installieren › Hinzufügen* und die BPL auswählen.
5. Liegt der Server nicht unter `Output\…\Bin` oder neben der BPL: *Tools › Optionen › Drittanbieter › Atlas*, Feld „Atlas-Server“. Die Seite zeigt an, ob der Server gefunden wird.
6. Delphi einmal neu starten: Atlas schaltet Help Insight und die Strukturhervorhebung der IDE ab, damit nichts doppelt erscheint; die IDE liest diese Schalter nur beim Start.

Einzelheiten und Fehlersuche: [docs/RAD-Studio.md](docs/RAD-Studio.md).

### Unterstützte Versionen

- RAD Studio bzw. Delphi **13 Florence** und **12 Athens** (ab 12.0). Das Plugin wird mit genau der Version gebaut, in der es läuft; die BPL trägt die Package-Version im Namen (`370` für Delphi 13, `290` für Delphi 12), damit beide nebeneinander liegen können.
- Klassische 32-Bit-IDE (BPL für Win32) und 64-Bit-IDE ab Delphi 12.3 (BPL für Win64).
- Windows 10 und 11.

Gebaut und geprüft wird bisher nur mit RAD Studio 13 in der 32-Bit-IDE. Was ohne Delphi-12-Installation und 64-Bit-IDE noch ungeprüft ist, steht in [docs/RAD-Studio.md](docs/RAD-Studio.md#ungeprüft).

### Claude Code und ohne Editor

- **Claude Code:** MCP-Werkzeuge und LSP als Plugin, siehe [Editors/ClaudeCode](Editors/ClaudeCode/README.md)
- **CI und Kommandozeile:** `AtlasServer.exe --check`, siehe [Linter-Modus](#linter-modus)

Ausführlich: [docs/Installation.md](docs/Installation.md).

## Benutzerdokumentation

- [Installation](docs/Installation.md) für RAD Studio, Claude Code und die Kommandozeile
- [IDE-Plugin](docs/RAD-Studio.md): alle Funktionen im Einzelnen
- [Einstellungen](docs/Einstellungen.md) des Plugins
- [Konfiguration](docs/Konfiguration.md) von `atlas.json` (erzeugt aus dem JSON-Schema mit `pwsh Tools/Update-ConfigDoc.ps1`)
- [Prüfregeln](docs/Regeln.md)
- [MCP-Werkzeuge](docs/MCP.md)
- [Benchmark](docs/Benchmark.md) der Leistungs-Zielwerte

## Aufbau

| Projekt | Inhalt |
|---|---|
| `Packages/Atlas.Text` | Package, nur RTL (frei von Windows und VCL); das IDE-Plugin bindet es als Quelltext ein |
| `Packages/Atlas.Common` | Package, frei von Windows und VCL |
| `Packages/Atlas.Windows` | Package für Windows-spezifische Funktionen, frei von VCL |
| `Application/AtlasServer` | Der Server (Konsolenprogramm, spricht LSP über stdin/stdout) |
| `Packages/Atlas.IDE.Expert` | Das IDE-Plugin (Designtime-Package; Win32 für die klassische IDE, Win64 für die 64-Bit-IDE ab Delphi 12.3), Schichten `Atlas.Core.*`, `Atlas.UI.*`, `Atlas.IDE.*` |
| `Tests/Atlas.Tests` | DUnitX-Tests |

Details zu Rollen, Benennung und Importregeln: [docs/Architektur.md](docs/Architektur.md).

## Voraussetzungen

- Delphi 12 Athens oder neuer, gebaut wird derzeit mit RAD Studio 13 (Win32 und Win64). Das IDE-Plugin muss mit der Delphi-Version gebaut werden, in der es laufen soll; der Server ist davon unabhängig.
- Das Testprojekt ist nur für Win64 eingerichtet, weil DUnitX in der Starter-Edition nur als Win64-Bibliothek vorliegt
- DUnitX (in RAD Studio enthalten, Umgebungsvariable `$(DUnitX)` der IDE)
- PowerShell für die Prüfskripte

## Bauen

In der IDE `Atlas.groupproj` öffnen und **Alle erstellen**. Die Reihenfolge Text → Common → Windows → Server → IDE-Plugin → Setup → Tests ist in der Projektgruppe hinterlegt. Text, Common, Windows und Server müssen für dieselbe Plattform gebaut werden, sonst findet der Server die Units der Packages nicht. Das IDE-Plugin ist für Win32 (klassische IDE) und Win64 (64-Bit-IDE ab Delphi 12.3) eingerichtet; welche BPL die IDE lädt, hängt von der IDE ab ([ADR 0008](docs/adr/0008-plattformen.md)).

Auf der Kommandozeile (RAD-Studio-Eingabeaufforderung bzw. nach `rsvars.bat`):

```bat
msbuild Atlas.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Die Ausgabe landet in `Output\<Plattform>\<Konfiguration>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

## Testen

Die DUnitX-Tests laufen ohne geöffnete IDE, nach dem Bau von `Atlas.Tests` (Win64):

```bat
Tests\Tests.bat              :: Funktionstests ohne Benchmarks
Tests\Tests.bat benchmark    :: nur die Benchmarks (Kategorie Benchmark)
Tests\Tests.bat alle         :: beides
```

Prüfskripte (laufen auch als GitHub Action):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # Packages halten ihre Abhängigkeiten ein
pwsh Tools/Check-ConsoleOutput.ps1         # kein Write/Writeln auf stdout
pwsh Tools/Check-TestCoverage.ps1          # jede Unit mit Logik hat Tests, jede Testunit läuft
```

## CI

- `server.yml`: Build der Projektgruppe über das IDE-Plugin `cc.ps1` (RAD Studio Starter hat kein msbuild, ADR 0007) für Win64 und Win32, samt Plugin-BPLs `Atlas.IDE.Expert370.bpl` für die klassische und die 64-Bit-IDE (Win32 und Win64, als Artefakte abgelegt), und DUnitX-Tests (nur Win64, ADR 0008). Ergebnisse als Check „DUnitX-Ergebnisse“ im Pull Request.
  - Der Job braucht einen selbst gehosteten Windows-Runner (Labels `self-hosted`, `windows`, `delphi`) auf dem Arbeitsrechner des Entwicklers. Er läuft im angemeldeten Benutzerkontext und nicht als Dienst, weil `cc.ps1` eine IDE startet, und nur, solange dieser Rechner eingeschaltet ist. Jeder Job startet eine eigene Scratch-IDE.
  - Er läuft nur mit der Repository-Variablen `DELPHI_RUNNER=true`; sonst meldet der Job „uebersprungen“ das in der Zusammenfassung des Laufs. `CC_SCRIPT` überschreibt den Pfad zu `cc.ps1`.
  - Ein neuer Push auf denselben Branch bricht den laufenden Build ab (`concurrency`).
- `package-dependencies.yml`: Package-Abhängigkeiten, stdout-Regel, Delphi-12-Verträglichkeit, Regelkatalog, Konfigurationsdoku und keine Embarcadero-Quellen in `Tests/`.

## Kommandozeile

| Parameter | Bedeutung |
|---|---|
| `--log <Datei>` | Logdatei, wird fortgeschrieben |
| `--log-level <Stufe>` | `debug`, `info` (Standard), `warning`, `error`; gilt für Logdatei und `window/logMessage` |
| `--trace <Datei>` | Mitschnitt aller JSON-Nachrichten (`-->` empfangen, `<--` gesendet) |

Werte gehen auch mit `=` (`--log=server.log`). `--stdio` und `--clientProcessId`, die Editoren anhängen, werden ignoriert.

`AtlasServer.exe --clear-cache` löscht alle Index-Caches unter `%LOCALAPPDATA%\Atlas`, die keine laufende Instanz nutzt. Der Ordner wird ohnehin auf 256 MB begrenzt, ältere Caches gehen zuerst.

### Linter-Modus

`AtlasServer.exe --check <Ziel>` prüft ohne Editor. Das Ziel kann eine `.dproj` (Hauptdatei und Units), ein Ordner (alle `.pas`, `.dpr` und `.dpk` darunter) oder eine Datei sein. `atlas.json` im Ordner des Ziels gilt wie im Editor. Fehlt sie, gilt die frühere `delphi-lsp.json` (ebenso `delphi-lsp-baseline.json` für die Baseline).

| Parameter | Bedeutung |
|---|---|
| `--format <Art>` | `text` (Standard, wie Compilermeldungen), `json`, `sarif` (SARIF 2.1.0 für GitHub Code Scanning) |
| `--output <Datei>` | Ergebnis in eine Datei statt auf stdout |
| `--rules <a,b>` | nur diese Regeln, z. B. `syntax` |
| `--units <a,b>` | nur diese Units: Name oder Glob-Muster für Pfade |
| `--min-severity <S>` | `hint`, `info`, `warning`, `error` |
| `--fail-on <S>` | ab welchem Treffer der Exit-Code 1 ist: `error` (Standard), `warning` oder `never`. So brechen Warnungen in Altprojekten keinen Pre-Commit-Hook ab |
| `--source-root <Ordner>` | Wurzel der SARIF-Pfade; Standard ist die Git-Wurzel über dem Ziel, sonst der Ordner des Ziels. Pfade darunter tragen `uriBaseId` `%SRCROOT%`, Dateien außerhalb erscheinen als absoluter `file:`-URI |
| `--profile <Name>` | Regelprofil (`standard`, `fast`, `strict`, `security`, `style` oder eigenes aus `profiles`); geht `profile` in `atlas.json` vor |
| `--baseline <Datei>` | bekannte Treffer ausblenden; ohne Angabe gilt `atlas-baseline.json` neben `atlas.json`, falls vorhanden. Der Editor blendet sie ebenso aus |
| `--update-baseline` | Baseline aus den aktuellen Treffern neu schreiben, Exit-Code 0. Auf stderr stehen zuerst die Einträge ohne Datei mit Pfad (umbenannte, verschobene oder gelöschte Dateien; sie fallen heraus), dann die Zähler: Treffer, Dateien, neu, entfernt, unverändert |
| `--changed [<Basis>]` | nur Dateien, die sich laut Git (bzw. SVN, siehe unten) gegenüber der Merge-Base mit `<Basis>` (Standard `main`) geändert haben; geänderte `.dfm`/`.fmx` prüfen ihre Unit, geänderte `.inc` alle Units, die sie einbinden, geänderte `.dproj`/`.dpk`/`.dpr`/`atlas.json` alles |
| `--diff <Ref>` | wie `--changed`, aber direkt gegenüber `<Ref>` |
| `--include-uncommitted` | mit `--changed`/`--diff` auch Index, Arbeitsverzeichnis und neue Dateien |
| `--changed-lines` | nur Treffer in geänderten Zeilen; zusammen mit der Baseline nur neue Treffer in geänderten Zeilen |
| `--suppression-stats` | statt der Treffer: wie oft jede Regel per `lsp-ignore` unterdrückt wird (häufigste zuerst, mit ungenutzten), als Text oder JSON; Exit-Code 0 |
| `--metrics` | statt der Treffer: Code-Metriken je Methode (Länge, Verschachtelungstiefe, zyklomatische und kognitive Komplexität, Parameter, Operanden, lokale Variablen, Ausstiege; #66, #980) mit den Grenzwerten aus `atlas.json` (`"max"` der Regeln `metric-*`); `--format text` schreibt einen Markdown-Bericht, `json` die Metrikdaten; Exit-Code 0 |
| `--todos` | statt der Treffer: offene TODO-Einträge (#68) aus `// TODO`, `// FIXME` und dem Format der IDE-To-Do-Liste `{ TODO 1 -oPerson -cKategorie : Text }` mit Priorität, Person und Kategorie; weitere Marken über die Option `"keywords"` der Regel `todo-comment`; `--format text` schreibt eine Markdown-Übersicht, `json` die Daten; Exit-Code 0 |

Exit-Code: 1, wenn ein Treffer `--fail-on` erreicht (Standard: mindestens ein Fehler), sonst 0; 3 bei Aufruf- oder Lesefehlern. Treffer aus der Baseline zählen nie.

Baseline (#97): Ein Eintrag in `atlas-baseline.json` merkt sich Datei, Regel, die umgebende Routine (voll qualifiziert wie `TFoo.Bar`, außerhalb einer Routine der Abschnitt wie `implementation`), einen Fingerabdruck der Zeile ohne Leerraum und einen Fingerabdruck des Codes ±2 Zeilen darum. Dieselbe Zeile in einer anderen Routine gilt deshalb als neu, ebenso ein Treffer, der in eine andere Routine wandert. Neu Einrücken, verschobene Zeilen und eine umbenannte Routine (Kontext gleich, alter Name nicht mehr in der Datei) überstehen die Baseline. Eine umbenannte oder verschobene Datei verliert ihre Einträge: Ihre Treffer erscheinen als neu, bis die Baseline aktualisiert ist. Ältere Dateien ohne Routine bleiben lesbar und werden beim nächsten Aktualisieren ergänzt. Unterdrückungskommentare für Treffer aus der Baseline melden kein `unused-suppression`. In Editoren aktualisiert der Befehl `atlas.updateBaseline` (`workspace/executeCommand`, Argument: URI des Projekts oder Ordners) die Baseline und antwortet mit den Zählern; er prüft dafür alle Dateien des Projekts und hält den Server so lange auf. In SARIF trägt jedes Ergebnis `partialFingerprints` (`atlasBaseline/v1` aus Regel, Routine und Zeile, `atlasContext/v1` aus dem Kontext, je mit laufender Nummer `:n` bei gleichen Werten in einer Datei); mit Baseline kommt `baselineState` hinzu: `new`, `unchanged` (als externe Unterdrückung) oder `absent` (Eintrag ohne Treffer). Text, JSON und Exit-Code enthalten nur die neuen Treffer.

In SARIF steht als `message.text` der englische Name der Regel aus dem Katalog, ohne Konfidenz-Zusatz. Die Konfidenz steht in `properties.confidence`, die deutsche Meldung des Treffers in `properties.detail`.

Jeder Regeltreffer hat eine Konfidenz (hoch, mittel, niedrig). Sie begrenzt den Schweregrad, auch wenn `rules` ihn höher einstellt: mittlere Konfidenz höchstens Warnung, niedrige höchstens Hinweis. Treffer unter `minConfidence` (Standard `medium`) bleiben aus. Die Konfidenz steht nie im Meldungstext, sondern als eigene Spalte in der Textausgabe (`[Konfidenz mittel]`), in JSON als `confidence`, im LSP als `data.confidence` und im Tooltip des Plugins als eigene Zeile.

In einer SVN-Arbeitskopie vergleicht `--changed` ohne Basis die Arbeitskopie mit BASE (`svn status`), `--changed <Rev>` und `--diff <Rev>` mit der Revision (`svn diff -r`); `--include-uncommitted` nimmt unversionierte Dateien dazu. Es gilt die nächstliegende Arbeitskopie über dem Ordner der Konfiguration (`.git` oder `.svn`), bei Gleichstand Git; `vcs.provider` in `%APPDATA%\Atlas\settings.json` legt die Art fest (`auto`, `git`, `svn`) oder schaltet ab (`off`). svn muss als Kommandozeilenwerkzeug installiert sein (TortoiseSVN mit Kommandozeilenwerkzeugen genügt).

Beispiele für einen Pre-Commit-Hook und eine GitHub Action, die nur Geändertes prüfen, liegen in [docs/Beispiele](docs/Beispiele).

### Prüfregeln

Alle Regeln sind in [docs/Regeln.md](docs/Regeln.md) beschrieben. Einzige Quelle ist der Regelkatalog `Packages/Atlas.Common/Katalog/regelkatalog.json` (englisch) mit der Übersetzung `regelkatalog.de.json`. Nach Änderungen `pwsh Tools/Update-RuleCatalog.ps1` ausführen; die CI prüft mit `-Check`, dass Katalog, Implementierung und Dokumentation übereinstimmen.

## Wichtig: stdout gehört dem Protokoll

Der Server spricht LSP über stdin/stdout. Jede zusätzliche Ausgabe auf stdout (`Writeln`, unbehandelte Exceptions) zerstört die Kommunikation mit dem Editor. Alle Diagnosemeldungen laufen über `ILogger` (`Atlas.Common.Logging`) an `OutputDebugString`, die Logdatei, `window/logMessage` und bei Fehlern stderr. Nach dem Start biegt der Server das stdout-Handle und `Output` auf stderr um, sodass auch Bibliotheken das Protokoll nicht stören können.

## Lizenzen

Atlas steht unter der MIT-Lizenz (`LICENSE`); die Lizenzvereinbarung für Installer und GetIt steht in `EULA.txt`; Drittanbieter-Komponenten mit Lizenztexten stehen in `THIRD-PARTY-NOTICES.md` (erzeugt von `Tools/Update-ThirdPartyNotices.ps1`).

Cache und Benchmark-Korpus bleiben lokal, VCL-Quellen werden nie eingecheckt. Der Index-Cache liegt unter `%LOCALAPPDATA%\Atlas`; RTL- und VCL-Quellen liest der Server nur aus der lokalen Delphi-Installation. `Tools/Check-NoEmbarcaderoSources.ps1` prüft in der CI, dass `Tests/` keine Datei mit Embarcadero-Copyright-Kopf enthalten.
