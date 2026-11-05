# Code-Analyse

Zurück zum [README](../../../README_DE.md)

Der Server prüft jede Unit beim Tippen.

- Treffer erscheinen als Wellenlinien, im Tooltip, gekürzt am Zeilenende und projektweit im andockbaren Fenster **„Atlas-Prüfung“** (Strg+Alt+P).
- Die Markierungen wandern beim Tippen mit.

## Oberfläche

### Fenster „Atlas-Prüfung“

- Befunde der Datei, des Projekts oder der Projektgruppe live
- Filter je Art, Kategorie und Text
- Gruppierung nach Datei, Regel oder Kategorie, sortierbare Spalten

| Bedienung | Wirkung |
|---|---|
| Enter | springt |
| Alt+Enter | korrigiert |
| Kontextmenü | Unterdrücken, Einstellen, Abschalten und Erklären der Regel |
| Kontextmenü „Alle sicheren Treffer von … korrigieren …“ | Sammelkorrektur mit Vorschau je Datei, abwählbar, ein Rückgängig-Schritt je Datei |

- „Offene zuerst“:
  - Die Unit im Editor steht angepinnt oben, darunter die übrigen geöffneten Units.
  - Nicht geöffnete folgen ausgegraut (oder normal bzw. ausgeblendet).
  - Auf Wunsch auch die aktive Unit ohne Befunde („Keine Befunde“).

Einstellungen: `fix.bulk`

### Wann die Prüfung läuft

- `problems.update` (*Tools › Optionen › Atlas › Prüfregeln › Prüffenster*):
  - live beim Tippen mit eigener Verzögerung `problems.liveDelayMs` in Millisekunden (100 bis 10000, Vorgabe 400)
  - beim Speichern
  - nur auf Anforderung über „Datei jetzt prüfen“ (Befehlspalette, Editor-Kontextmenü, eigenes Kürzel Strg+Umschalt+Alt+P `keys.checkFile`, Knopf im Fenster „Atlas-Prüfung“, Klick auf die Live-Prüfung der Statusleiste)
- Die frühere Einstellung „Laufende Prüfung beim Tippen“ wird übernommen

### Befund-Hover und Optionen

- **Befund-Hover** mit Schweregrad, Regel und Aktionszeile „Alt+Enter: Korrektur“, „Für diese Zeile unterdrücken“, „Regel einstellen…“
- **Seite „Prüfregeln“** in den Optionen:
  - je Regelgruppe ein Hauptschalter und eine Tabelle mit Schweregrad, Ausnahmen und Optionen jeder Regel
  - Suche und Katalogtext mit Beispielen

## Prüfregeln

**313 Prüfregeln** in vier Kategorien: 204 Fehler, 99 Code-Smells, 5 Schwachstellen, 5 Sicherheits-Hotspots. Darunter:

### Korrektheit

- nicht gesetztes `Result`
- möglicherweise uneingeleitete Variablen
- unerreichbarer Code
- ungenutzte Variablen, Parameter und Zuweisungen
- deklarierte, aber nicht implementierte Methoden (auch bei Sonderformen wie `class constructor`, der Kurzform der Implementierung `function Foo;`, `Execute()` mit leeren Klammern, Constraints nur in der Deklaration, Rümpfen aus `asm` oder `external` und Methodenzuordnungen, die weder als fehlende Überladung noch als unbekannte Direktive gelten)
- fehlendes `override`, verdeckte virtuelle Methoden
- Überläufe, Gleitkomma-Vergleiche
- `raise` in `finally`
- übersehener Vorrang von `not` (`not X in Menge`)
- leere Anweisung nach `then`/`do`/`else`
- Schleifen einen Schritt zu weit (`0 to Liste.Count`)
- Listen in der eigenen Schleife verändert (`Delete` in einer Vorwärtsschleife)
- Objekte nach `Free` weiter benutzt (mit Sprung zur Freigabe)
- Zugriff vor der nil-Prüfung (`X.Name` vor `if Assigned(X)`)
- Freigabe und Besitz:
  - Felder außerhalb des Destruktors ohne `nil` freigegeben
  - im Konstruktor erzeugte Felder, die der Destruktor nie freigibt
  - Destruktoren, die ein Feld benutzen, das nach einer Exception im Konstruktor noch nil ist (`FZeilen.Clear`, wenn vorher `TFileStream.Create` warf; Korrektur `if Assigned`)
  - Windows-Handles aus `CreateFile`, `FindFirstFile`, `RegOpenKeyEx`, `LoadLibrary`, `GetDC` oder GDI-Objekte, die nicht auf jedem Weg geschlossen werden (Korrektur `try … finally CloseHandle`)
  - in `initialization` oder einem `class constructor` erzeugte Objekte, die `finalization` bzw. der `class destructor` nie freigibt
  - Konstruktoren und Destruktoren ohne `inherited`
  - `Destroy` statt `Free`
- `FillChar`/`Move`/`GetMem` auf Records mit Strings oder Interfaces
- `PChar` auf temporäre Strings
- `out`-Parameter, die vor dem Setzen gelesen werden
- `Find` auf unsortierten `TStringList`s
- `DelimitedText` ohne `StrictDelimiter`
- Änderungen an der globalen `FormatSettings`, die die ganze Anwendung und alle Threads treffen (Korrektur: lokale `TFormatSettings`)
- `Writeln` in Programmen ohne Konsole
- `raise` im Destruktor
- doppelte Bedingungen und gleiche Zweige
- `case` über Aufzählungen, denen Werte fehlen
- `DisableControls`/`BeginUpdate`/`Screen.Cursor` ohne `try`/`finally`
- `StrToInt` auf `Edit.Text` ohne Prüfung
- Zahlen aus Datenbank, Registry oder Text ohne Bereichsprüfung in eine Aufzählung umgewandelt (Korrektur mit `InRange`)
- `CreateProcess` mit unveränderlicher Befehlszeile wie `PChar('notepad.exe')` (Korrektur mit Kopie und `UniqueString`)
- Zugriff in `OnCreate` auf ein Formular, das die `.dpr` erst später erzeugt
- Exceptions:
  - `on E: Exception` vor einem spezielleren Handler, der so nie erreicht wird (die Korrektur zieht ihn nach vorn)
  - `raise E;` im Handler, das die ursprüngliche Absprungstelle verliert (Korrektur `raise;`)
- `Dict[Key]` ohne `ContainsKey` oder `TryGetValue`
- `Copy(S, 0, N)` und `Pos(…) > -1` (Strings zählen ab 1)
- Ereignisse wie `FOnChange(Self)` ohne `Assigned` aufgerufen (die Korrektur ergänzt die Prüfung)
- von Hand freigegebene Elemente einer besitzenden `TObjectList` (doppelte Freigabe)
- `TStringList.Create;` ohne Zuweisung (die Korrektur legt eine Variable mit `try`/`finally` an)
- Interfaces und Referenzzählung:
  - `Self` als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann (eigene Referenzzählung im Konstruktor, `TInterfacedObject` nach `inherited AfterConstruction`; die Korrektur verschiebt den Aufruf vor `inherited`)
  - Formulare und andere Komponenten, die als Interface gespeichert (`Bus.Anmelden(FAnsicht as IBeobachter)`) und dann ohne Abmeldung freigegeben werden (die Korrektur fügt die Abmeldung vor `Free` ein)
- Vergleiche mit `Null`, deren Ergebnis von `NullEqualityRule` abhängt (Korrektur `Feld.IsNull` bzw. `VarIsNull`)
- Speicher aus `GetMem` oder `New`, der nie freigegeben wird (die Korrektur ergänzt `try … finally FreeMem`)
- Objekte, die `AddObject` in eine `TStringList` ohne Besitz legt (die Korrektur setzt `TStringList.Create(True)`)
- dasselbe Feld oder dieselbe Property zweimal hintereinander gesetzt (`Panel.Left` doppelt statt `Left`/`Top`)
- Bedingungen, die immer wahr oder falsch sind (`if (Anzahl > 0) or True`, `if DEBUG_MODUS then` mit einer Konstanten; die Korrektur entfernt den toten Zweig)
- Schleifen und Rekursion:
  - Schleifen ohne Ausgang (`while True do` ohne `Break`, `Exit` oder `raise`)
  - Schleifenbedingungen, die sich im Rumpf nie ändern (`while I < Liste.Count` ohne `Inc(I)`)
  - Rekursion ohne Abbruch (eine Routine, die sich auf jedem Pfad selbst aufruft)
  - Schleifen, die höchstens einmal laufen, weil jeder Weg durch den Rumpf mit Exit, Break oder raise endet (Option `allowFirstElement` für „erstes Element holen“)
- vertauschte Argumente von Pos, StartsText oder ContainsText
- Ganzzahldivision an eine Gleitkommazahl
- Strings, dynamische Arrays, Interfaces und Typparameter im varianten Teil eines Records oder hinter `file of` (die Korrektur verschiebt das Feld vor `case`)
- Interface-GUIDs, die nicht die Form `{8-4-4-4-12}` haben (die Korrektur erzeugt eine neue)
- Interfaces und Strings, die über `Pointer(FIntf) := …` an der Referenzzählung vorbei zugewiesen werden (Korrektur `[weak]` bzw. `[unsafe]`)
- statische Arrays und Records ab 2 GB, aus den Deklarationen berechnet
- `noreturn`-Routinen (Delphi 13), die am Ende des Rumpfs oder über `Exit` doch normal zurückkehren können
- harte Umwandlungen zwischen Klassen, die weder Vorfahr noch Nachfahr voneinander sind (`TButton(mEdit)`; still beim Zugriffsklassen-Trick, Option `allowTypes`, Korrektur `(mEdit as TButton)`)
- `@S[1]` bzw. `PChar(@S[1])` als Adresse der Zeichen (Bereichsfehler bei leerem String; Korrektur `PChar(S)`)
- Formatstrings, die nicht zu ihren Argumenten passen (`Format('%d', [Name])`, zu wenige Argumente, `%q`)

### Threads

- VCL-Zugriff aus Threads
- Sperren ohne `finally`
- `FreeOnTerminate`-Fallen
- `Synchronize` im Destruktor
- `threadvar` mit Strings
- `Application.ProcessMessages` in Schleifen und Ereignis-Handlern
- `TThread.Queue(nil, …)` in Packages (Korrektur auf den eigenen Wrapper)
- `Sleep`/`WaitFor` in Formularen und Ereignis-Handlern, die die Oberfläche einfrieren
- Schleifen in `Execute`, die `Terminated` nie prüfen (die Korrektur ergänzt es)
- `CreateAnonymousThread` ohne `Start` (die Korrektur hängt es an)
- `TTask.Run` ohne `try … except`, dessen Exceptions verloren gehen (die Korrektur schließt den Rumpf ein)
- Variablen und Sammlungen von außerhalb, die `TParallel.For` oder in einer Schleife gestartete Tasks ohne Sperre schreiben (die Korrektur nimmt `TInterlocked` bzw. eine `TMonitor`-Sperre)
- Zähler, die `Execute`, `TTask.Run` oder anonyme Threads ohne Sperre mit `Inc` erhöhen (die Korrektur nimmt `TInterlocked.Increment`)

### Datenbank

- `while not Q.Eof`-Schleifen ohne `Q.Next` auf jedem Weg (die Korrektur fügt es ein)
- `Edit`/`Append` ohne `Post` oder `Cancel` (Korrektur mit `try … except Cancel`)
- Transaktionen ohne `Rollback` bei Exceptions (FireDAC, IBX, dbExpress, ADO; Korrektur mit `try … except Rollback`)
- `UPDATE`/`DELETE` ohne `WHERE` im Code, in Konstanten und in der Formulardatei (Option `allowTables` für absichtlich geleerte Tabellen)
- `SELECT *` (standardmäßig aus; die Korrektur setzt die persistenten Felder der Datenmenge ein)

### Compiler vorab

Compilerfehler schon beim Tippen, ohne Build.

#### Zusammenspiel mit dem Build

- Meldet der nächste Build denselben Fehler an derselben Zeile, zeigt Atlas nur einen Eintrag mit der Marke „Atlas + dcc“ und „vom Compiler bestätigt (E2035)“.
  - Einstellung „Bestätigte Compilermeldungen“: zusammenführen oder beide zeigen.
- Die Spalte „Compiler“ im Fenster „Atlas-Prüfung“ nennt den Code.
- Unter Prüfregeln › Compiler vorab schalten der Hauptschalter alle Regeln der Gruppe und „Regeln der Stufe T prüfen“ nur die ab, die Ausdruckstypen brauchen.
- Der Compilercode in Meldung, Spalte und Hover lässt sich ausblenden.
- Die Meldungen nennen den Code, den Delphi 13 meldet (#1382, etwa E2058/E2059, E2123, W1008, W1019, E1030; mit `delphiVersion` unter 13 das ältere W1030).
- Typen vergleichen diese Regeln wie der Compiler (#1324):
  - Aliase über Units hinweg (`TIdPort = Word`, `LongInt = Integer`, `IUnknown = IInterface`)
  - Unit-Qualifizierer, Kommentare und Direktiven im Kopf zählen nicht
  - `type A = type B` bleibt ein eigener Typ
  - Konstanten rechnen Typumwandlungen wie `Cardinal(-1)` mit
- `TextFile`, `Text` und die alte `object`-Syntax (`New(P, Init)`, `Dispose(P, Done)`, `Fail`) kennt die Namensauflösung, sodass sie kein falsches E2003 mehr geben.

#### Deklarationen und Implementierung

- Methodenköpfe der Implementierung, die von der Deklaration abweichen (Parameter, `const`/`var`, Ergebnistyp, Aufrufkonvention; wie E2037, die Korrektur gleicht eine der beiden Seiten an)
- Interface-Methoden, die in der Klasse fehlen (wie E2291, auch mit abweichendem Kopf oder einer Zuordnung für ein nicht genanntes Interface; die Korrektur deklariert und implementiert sie)
- Felder nach Methoden oder Properties im selben Abschnitt, die FPC übersetzt, Delphi aber nicht (wie E2169; die Korrekturen verschieben das Feld nach oben oder setzen `var` davor)
- Überladungen ohne `overload` oder mit gleichen Parametern (wie E2254, E2267, E2252, E2301; die Korrektur hängt überall `overload;` an)
- doppelt deklarierte Bezeichner im selben Bereich und doppelte Units in `uses` (wie E2004; überladene Array-Properties sind erlaubt, #1383; die Korrektur entfernt die zweite)
- `override` ohne passende virtuelle Methode im Vorfahren, auf eine statische oder `final`-Methode und Klassen, die von einer `sealed`-Klasse ableiten (wie E2137, E2170, E2352, E2353; die Korrektur übernimmt die Signatur des Vorfahren in Deklaration und Implementierung, auch bei Tippfehlern wie `Destory`)
- `Create` auf einer Klasse mit nicht überschriebenen abstrakten Methoden (wie W1020; eine `abstract`-Klasse ohne abstrakte Methoden bleibt still wie bei dcc, #1383; die Meldung nennt die offenen Methoden, die Korrektur überschreibt sie in einer Klasse der Datei)
- `inherited Name(…)` auf eine im Vorfahren abstrakte Methode (eine Warnung: Der Aufruf löst zur Laufzeit EAbstractError aus, Delphi 13 übersetzt ihn ohne E2373, #1383; die Korrektur entfernt den Aufruf)
- `Create` über eine Klassenreferenz (`class of TBasis`), deren Konstruktor nicht virtuell ist, sodass immer der Konstruktor der Basisklasse läuft (wie E2391; die Korrektur ergänzt `virtual` und `override` in den Nachfahren)
- Integer und HRESULT zwischen Interface-Methode und Implementierung vertauscht (wie W1008; die Korrektur gleicht den Ergebnistyp an)
- Deklarationen, die dcc schon wegen ihrer Form ablehnt (Regel `declaration-invalid`: E2006, E2024, E2062, E2128, W1029, #1380):
  - `packed` vor einem einfachen Typ
  - Ergebnistyp `file`
  - virtueller Konstruktor in einem `object`-Typ
  - Property ohne `read`/`write` in Interface oder `automated`-Abschnitt
  - gleiche Konstruktor-Parameter bei C++-Ausgabe
- unvollständige Typen als Vorfahr, in der Interface-Liste oder als eigenes Record-Feld (wie E2086)
- `sealed`-Klassen mit abstrakten oder nicht implementierten geerbten abstrakten Methoden (wie E2383, E2539, E2540)
- zwei default-Properties verschiedenen Namens (wie E2131)
- Feldselektoren hinter Klassen-Properties (wie E2459)
- Unit-Routinen, deren Rumpf vom interface-Kopf abweicht (wie E2037)
- Assign ohne var-Parameter des eigenen Typs (wie E2617)
- varargs ohne external unter Win32 (wie E2277)
- dispinterface-Deklarationen mit Vorfahr, ohne GUID, mit Methodendirektiven wie `stdcall` oder mit `read`/`write` an Properties (wie E2228–E2231; die Korrekturen entfernen Vorfahr bzw. Direktive und fügen eine GUID ein)

#### Units, Dateien und Direktiven

- Units in `uses`, die der Compiler weder im Projekt noch in Such- und Bibliothekspfaden findet (auch als `.dcu`; wie F2613, mit ähnlichen Namen, Korrekturen für das Namespace-Präfix oder einen fehlenden Suchpfad in der `.dproj`)
- fehlende Dateien aus `in '…'` (auch ohne Projekt), Packages aus `requires` und Units, die sich selbst einbinden
- Attribute wie `[TestFixture]`, die Delphi still übergeht, weil ihre Unit fehlt (wie W1074, nach `{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR}` wie E1074; die Korrektur ergänzt die Unit)
- bedingte Direktiven (wie E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573; die Korrekturen ergänzen `{$ENDIF}`, entfernen eine überzählige Direktive oder korrigieren den Tippfehler):
  - offene oder überzählige bedingte Direktiven
  - fehlende Symbole, unbekannte Direktiven und `{$WARN}`-Bezeichner
  - unpaarige `{$PUSHOPT}`/`{$POPOPT}`
  - ungültige Werte für `{$ALIGN}`
- Compileranweisungen, die dcc ablehnt oder selbst meldet (wie W1054, H1054, E2222, E2224, E2560, E1030, F1026, E1026, E2245; #1379):
  - `{$MESSAGE WARN|HINT}` mit ihrem Text
  - `{$WEAKPACKAGEUNIT ON}` mit `{$DENYPACKAGEUNIT ON}`
  - `{$DESIGNONLY}`/`{$RUNONLY}` in einer Unit
  - `{$OBJTYPENAME}` an einem Alias
  - `{$CODEPAGE}` über 65535
  - fehlende Dateien aus `{$I}` und `{$R}` (gesucht wie von dcc: neben der Unit, Suchpfade, `DCC_IncludePath`, `DCC_ResourcePath`, Bibliothek)
  - Include-Dateien, die sich selbst einbinden

#### Anweisungen und Ablauf

- Vergleiche wie `Result = 0;` als eigene Anweisung (wie E2014; die Korrektur ersetzt `=` durch `:=`)
- doppelte `case`-Marken, auch über Bereiche und Konstanten mit gleichem Wert und in varianten Records (wie E2030, E2027; die Korrektur entfernt den späteren Wert)
- `Break` und `Continue` außerhalb einer Schleife sowie `Break`, `Continue` und `Exit`, die einen `finally`-Block verlassen (wie E2097, E2126; die Korrektur ersetzt `Break` durch `Exit`)
- `raise;` ohne Argument außerhalb eines `except`-Blocks, etwa in einer lokalen Prozedur, die aus dem Handler gerufen wird (wie E2145)
- falsch verwendete Sprungmarken: doppelt gesetzt, nie gesetzt, nicht deklariert oder mit `goto` in einen `try`-Block hinein bzw. aus ihm heraus (wie E2073, E2074, E2093, E2127)
- Schleifenvariablen:
  - die im Rumpf zugewiesen, mit `Inc`/`Dec` verändert oder als `var`-Parameter übergeben werden oder keine einfache lokale Variable sind (wie E2081, W1015, E1019; die Korrekturen stellen auf `while` um bzw. verwenden `for var`)
  - die nach dem normalen Ende der Schleife gelesen werden (wie W1037, Korrektur nach `while`)
- Zählschleifen mit `to`, die nie laufen (`High … to Low`, konstante Grenzen wie `10 to 1`; wie H2135, Korrektur `downto`)
- Bedingungen in if, while und until, die kein Boolean sind (wie E2012; die Korrektur ergänzt <> 0, > 0, <> nil bzw. Assigned)
- for-in über Typen ohne Enumerator (wie E2430, E2431)
- Bedingungsausdrücke `X := if C then A else B` in Projekten, die noch mit Delphi 12 oder älter übersetzen müssen (wie E2029; die Korrektur, auch für die ganze Unit, wandelt in eine `if`-Anweisung um)
- ungültige Anweisungen in `asm`-Blöcken (`asm-invalid`):
  - fehlender Operand
  - Register verschiedener Größe wie `mov al, ebx`
  - `lea` mit einer Zahl
  - `db` mit einer lokalen Variablen
  - `OFFSET a + OFFSET b`
  - Zahlen über 64 Bit
  - zu lange Stringkonstante für das Register
  - Division durch null

#### Properties

- Getter, Setter und Felder hinter `read`/`write`, die fehlen, überladen sind, eine falsche Signatur oder einen `var`-Parameter haben, Klassen- und Instanzmitglieder mischen oder ungültige Feldselektoren nutzen (wie E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562; die Korrektur legt ein fehlendes `FName`, `GetName` oder `SetName` an)
- Zuweisungen an ein Feld eines Records, den eine Property, Default-Property oder Funktion nur als Kopie liefert, und an Konstanten (wie E2064; die Korrektur weist über eine lokale Variable zu und schreibt zurück)
- Zuweisungen an Properties ohne `write` und Lesen von Properties ohne `read` (wie E2129, E2130; die Korrekturen rufen `Clear` statt `Count := 0` auf, weisen das Feld hinter `read` zu oder legen den Setter an)

#### Aufrufe und Argumente

- Aufrufe mit zu vielen oder zu wenigen Argumenten für eine Routine ohne Überladung (wie E2034, E2035; die Korrektur öffnet den Parameter-Hint in den Klammern)
- Aufrufe überladener Routinen und Methoden:
  - zu denen keine Überladung passt, etwa ein Gleitkommawert, wo nur `Integer` und `string` angeboten sind (wie E2250)
  - oder die mehrdeutig sind, weil sich die Überladungen nur in Parametern mit Standardwert unterscheiden (wie E2251)
  - geprüft nur, wenn alle Überladungen bekannt sind
- ungültige Argumente für var- und out-Parameter: Konstanten, Properties, Funktionsergebnisse und Ausdrücke (wie E2197, E2192, E2036; `Slice` an var- und out-Open-Arrays und String-Elemente wie `S[1]` bleiben still wie bei dcc, #1383; die Korrektur übergibt eine lokale Variable)
- `@` vor einem Ausdruck (wie E2036)
- unzulässige Standardwerte von Parametern (mehrere Namen mit einem Standardwert, Parameter ohne Standardwert nach einem mit, `var`/`out`, Records und große Mengen; wie E2237, E2238, E2239, E2268, E2146; die Korrekturen deklarieren die Namen einzeln bzw. verschieben die Parameter mit Standardwert ans Ende)
- lokale (verschachtelte) Routinen als Prozedurvariable oder Argument eines prozeduralen Typs (wie E2094, E2278; die Korrektur verschiebt die Routine auf Unit-Ebene)

#### Generics

- Typargumente, die die Einschränkung ihres Typparameters verletzen (`class`, `record`, `constructor`, Interface oder Basisklasse), `T.Create` ohne `constructor`-Einschränkung und Methodenaufrufe auf Werten eines unbeschränkten `T` (wie E2511–E2515, E2568, E2571; die Korrektur ergänzt die Einschränkung)
- generische Deklarationen, die Delphi ablehnt (wie E2528, E2552, E2553, E2570, E2574; die Korrektur entfernt `type`):
  - jetzt auch Typparameter an Konstruktoren
  - eine Klasse neben `class`/`record` oder zwei Klassen als Einschränkung mit Klassen aus anderen Units wie `TStream` (Symbolindex)
  - lokale Routinen in generischen Methoden und Methoden generischer Typen
  - `type TList<Integer>`
- Aufrufe generischer Methoden ohne Typargumente, deren Typparameter sich nicht ableiten lässt, weil er in keinem Parameter vorkommt oder die Argumente Zahl und Zeichenkette sind (wie E2531, E2532; Stufe T)

#### Typen

- unbekannte Typnamen in Deklarationen, Typumwandlungen und Zeigerzielen sowie Namen, die kein Typ sind (wie E2003, E2005, E2564; die Korrektur ergänzt die deklarierende Unit in uses)
- `New`, `Dispose` und `SetLength` ohne Länge auf dynamischen Arrays (wie E2255, E2256, E2246, E2307, E2308; Korrekturen `A := nil` und `SetLength(A, 1)`)
- inkompatible Typen in Zuweisung, Aufruf, Vorgabewert und Operator (`type-mismatch`, #1369, wie E2008, E2009, E2010, E2015, E2033, E2089):
  - `S := 1` mit `S: string`, `'a' + 1`, `div` auf `Double`, `not` auf einem String, ein `AnsiString` an `var S: string`, `Integer(1.5)` oder ein Ereignis mit anderer Parameterliste
  - gemeldet wird nur, was sicher feststeht (keine Aliase mit `{$IFDEF}`, keine Überladungen, keine Operatorüberladung)
  - Delphi 13 meldet Zugriffsmethoden von Eigenschaften und `Dispose`/`New` mit Länge als E2008, darum melden `property-accessor-invalid` und `dynamic-array-misuse` jetzt auch diesen Code
- Operationen, die eine Typart verlangen, die der Operand sicher nicht hat (`type-kind-required`, #1370):
  - Index, `^`, Punkt oder `with` auf einer Zahl, einem Boolean, Zeichen oder Aufzählungswert (wie E2016, E2017, E2018)
  - `^` auf Klassen, Records und Interfaces (die Korrektur entfernt es vor einem Punkt)
  - falsche Vorfahren von object-Typen, Klassen und Class-Helpern sowie Record-Helper für Klassen (wie E2019, E2021, E2022, E2474)
  - `New`/`Dispose` mit Konstruktor bzw. Destruktor und `TypeOf` auf einfachen Typen (wie E2467, E2019)
  - eine Methode ohne `class` über den Klassentyp außerhalb der Klasse und ihrer Nachfahren (wie E2076)
  - `Slice` außerhalb eines Arguments für ein offenes Array (wie E2193)
  - Records in `array of const` (wie E2150) sowie Klassen, Records oder Interfaces in `Write`/`Read` (wie E2054, E2055; Korrektur `ToString`)

#### Konstanten, Zahlen und Strings

- Fehler in konstanten Ausdrücken (wie E2098, E2099, E2011, E1012, W1012, E2102, E2028, E2572):
  - Division durch null
  - Überlauf (mit lauter Operanden mit Vorzeichen schon über Int64 hinaus, etwa `High(Int64) + 1`)
  - Bereiche wie `array[5..1]`
  - Werte außerhalb des Typs (ein Fehler wie E1012, eine Warnung wie W1012 nur, wenn der Wert als gleich breite Zahl mit anderem Vorzeichen passt)
  - konstante Indizes außerhalb eines statischen Arrays und case-Marken außerhalb des Typs des case-Ausdrucks
  - zu große Hex-Literale
  - Mengen mit mehr als 256 Elementen
  - Zahlen in Sichtbarkeitsmengen von `{$RTTI}`
- vorzeichenbehaftete und vorzeichenlose Operanden in Vergleichen oder Rechnungen gemischt (Integer mit Cardinal, alles mit UInt64; wie W1023, W1024, W1073; die Korrektur wandelt den vorzeichenlosen Operanden in Int64 um)
- Zuweisungen mit möglichem Datenverlust, standardmäßig aus (Int64 oder NativeInt an Integer, einstellbare Paare wie Double>Single; wie W1072, W1066, Ganzzahlen ohne Code, weil Delphi 13 W1071 nicht meldet, #1383; die Korrekturen wandeln ausdrücklich um oder vergrößern den Zieltyp)
- typisierte Konstanten und Zeigerkonstanten (die Korrekturen machen aus der Konstante eine initialisierte Variable bzw. schreiben nil):
  - typisierte Konstanten, die per Zuweisung oder als var-Argument verändert werden (wie W1016, W1017; mit {$J-} wie E2064, E2197; mit {$J+} vor der Deklaration still wie dcc, #1328)
  - 0 statt nil bei Zeigerkonstanten (wie W1013)
- überschrittene String-Grenzen (die Korrekturen deklarieren das Ziel als string bzw. teilen das Literal):
  - Literale, die an `string[N]`/ShortString gekürzt werden (wie W1014)
  - Literale über 255 Zeichen vor Delphi 12 (wie E2056)
  - resourcestrings über 4096 Zeichen (wie E2381)
- Umwandlungen zwischen Unicode- und ANSI-Strings (wie W1057, W1058, W1059, W1060, W1062, W1050, W1068; nach `{$WARN … OFF}` still wie dcc; die Korrekturen wandeln ausdrücklich um bzw. verwenden `CharInSet`, #1377):
  - implizit in `string` oder `AnsiString` bei Zuweisungen, Inline-Variablen und Argumenten
  - ausdrückliche Umwandlungen nach `{$WARN EXPLICIT_STRING_CAST ON}`
  - Stringkonstanten mit Zeichen, die der ANSI-Codepage fehlen
  - `C in ['0'..'9']` mit einem `Char` und `S[1] := 'x'` nach `{$WARN IMMUTABLE_STRINGS ON}`

#### Sprachversion, Plattform und unsicherer Code

- Sprachmerkmale, die die älteste unterstützte Delphi-Version des Projekts noch nicht kennt (If-Ausdruck, `is not`, `not in`, Inline-Variable, mehrzeiliger String …; `language-feature`):
  - Maßstab ist `minDelphiVersion` in atlas.json, etwa `"12"` für Code, den Delphi 12 und 13 übersetzen müssen.
  - Code-Aktionen und Schnellbefehle erzeugen solche Merkmale dann nicht.
- Symbole und Units mit `deprecated`, `experimental`, `platform` oder `library` (wie W1000–W1007):
  - wie bei dcc ab Werk alle vier Arten
  - still, wo die `.dproj` (`DCC_SYMBOL_PLATFORM = false` …) oder `{$WARN …}` die Warnung abschaltet
  - dazu die .NET-Direktive `{$UNSAFECODE}` als plattformspezifisch (wie W1002)
- unsicherer Code nur dort, wo die Warnung wie bei dcc eingeschaltet ist (`{$WARN UNSAFE_CODE ON}`, `DCC_UNSAFE_CAST = true` …; Regel `unsafe-code`, #1378):
  - `@` auf Variablen, Felder und Parameter (wie W1047)
  - Umwandlungen eines `Pointer` in eine Klasse (wie W1048)

#### OLE-Automation (#1373)

- im veralteten Abschnitt `automated` (wie E2175–E2182, E2096, E2185):
  - Felder, Konstruktoren, dynamic- und message-Methoden
  - andere Aufrufkonventionen als register
  - doppelte dispids
  - neu deklarierte Properties und die Klauseln index, stored, default und nodefault
  - read oder write dort auf ein Feld
  - Records, Zeiger und Mengen dort als Typ
- Records oder Zeiger als Argument von Aufrufen über Variant oder OleVariant und unbenannte nach benannten Argumenten (wie E2160, E2281, E2166)

#### Compilerhinweise ohne eigene Regel (`compiler-hints`, #1381)

- published in einer Klasse, die ohne RTTI übersetzt wird (wie W1055; still bei `{$M+}` oder einem Vorfahren mit RTTI wie `TPersistent`)
- `Initialize`/`Finalize` auf einem `Integer`, `Double` oder ähnlichen Typ (wie H2243) oder auf einem `PString` statt `P^` (wie H2244)
- `inline-not-expanded` meldet H2445 jetzt auch bei inline-Funktionen, deren Rumpf nichts aus anderen Units benutzt, und nicht mehr `TList<T>.Add` und Ähnliches wegen System.TypInfo (Aliase von Deklarationen aus System) oder Zyklen bei Rümpfen nur mit eingebauten Typen und Intrinsics

### Ausnahmen

- leere `except`-Blöcke
- Auffangen ohne erneutes `raise`
- erzeugte, aber nicht ausgelöste Ausnahmen
- leere `finally`-Blöcke
- Konstruktoren, die `try` vor `inherited Create` betreten (die Korrektur zieht den Aufruf vor `try`)

### Komponenten und Formulare

- fehlendes `inherited`, `Notification`, falsche `default`-Werte
- Felder ohne Objekt im Formular und umgekehrt
- Datenbindungen und Datenquellen in DFM-Dateien
- Message-Handler (`message WM_SIZE`) ohne `inherited`
- IDE-Notifier ohne `RemoveNotifier` (die Korrektur merkt den Index und meldet beim Entladen ab)
- DUnitX-Tests ohne Prüfung
- `inherited` an der falschen Stelle (im Destruktor vor dem Freigeben eigener Felder, im Konstruktor nach dem Zugriff auf geerbte Properties; die Korrektur verschiebt es)
- `inherited Laden` im überschriebenen `Speichern` (die Korrektur setzt den eigenen Namen, Option `allowed`)
- Getter, die den Zustand ihres Objekts ändern (`Inc(FAbrufe)` in `GetWert`, Lazy-Initialisierung erlaubt)
- `Equals` ohne `GetHashCode` überschrieben (Korrektur mit `THashBobJenkins`) und Records mit `class operator Equal` als Dictionary-Schlüssel ohne Comparer
- Formular-Units ohne `{$R *.dfm}` (die Korrektur fügt es ein) und `{$R}` auf eine fehlende Formulardatei
- Formulare, die `Application.CreateForm` und zusätzlich der Code erzeugt (die Korrektur entfernt die Zeile aus der `.dpr`)
- Handler in geerbten Formularen, die den Handler des Vorfahren nicht mehr aufrufen (die Korrektur fügt `inherited;` ein)
- Formulare, die sich im eigenen Ereignis-Handler freigeben (die Korrektur nimmt `Release` bzw. `Action := caFree`)
- Verweise der Formulardatei auf Komponenten eines anderen Formulars oder Datenmoduls, dessen Unit nicht in den uses steht (`Connection = Form1.Connection`; die Korrektur ergänzt die Unit)

### Laufzeitumgebung

- Dialoge (`ShowMessage`, `MessageDlg`, `InputBox`) in Konsolenprogrammen, Windows-Diensten und DLLs ohne Formulare
- `LoadFromFile`/`SaveToFile` und `TFile.ReadAllText` ohne Kodierung (Korrektur `TEncoding.UTF8`)
- Schreiben nach `HKEY_LOCAL_MACHINE` (Korrektur `HKEY_CURRENT_USER`)
- Laufzeiten mit `Now` gemessen (Korrektur `TStopwatch`)

### Dateien und Systemnähe

- Pfade ohne Trennzeichen zusammengesetzt (`TPath.GetDocumentsPath + 'export.csv'`, Korrektur `TPath.Combine`)
- feste Laufwerks-, Benutzer- und Netzwerkpfade (Option `allowUnits`)
- Dateinamen mit `=` statt `SameFileName` verglichen (still bei plattformabhängigen Vergleichen mit `SameText` und in Test-Units)
- DLL-Exporte ohne Aufrufkonvention oder mit Strings, dynamischen Arrays, Objekten oder Interfaces ohne GUID (Korrektur `stdcall`, Option `allowShareMem`)

### Sicherheit

- SQL- und Befehlsinjektion
- Pfadmanipulation
- schwache Kryptografie
- abgeschaltete TLS-Prüfung
- unsicheres HTTP und Zufall
- Trojan Source (Bidi-Steuerzeichen, unsichtbare und verwechselbare Zeichen)
- Steuerzeichen und ungültige UTF-8-Bytes (#1327):
  - Eine Datei ohne BOM liest Atlas wie dcc nur dann als UTF-8, wenn sie ganz gültiges UTF-8 ist.
  - Ein zufällig gültiges UTF-8-Paar in einer ANSI-Datei macht deren Umlaute nicht zu Fehlern.
  - U+FFFD meldet `control-char` im Kommentar nicht, im String nur als Hinweis.

### Architektur und Stil

- Abhängigkeiten:
  - verbotene uses
  - Importregeln nach Rollen
- bis zum Ende der Unit abgeschaltete Compiler-Warnungen, Hinweise, Bereichs- oder Überlaufprüfungen (Option `allow`)
- `with`
- überflüssige Klammern und `begin … end`
- Bedingungen und Schleifen ohne `begin … end` (Korrektur für die Anweisung, die Methode oder die Datei; schaltet die Regel für überflüssiges `begin … end` stumm)
- Dateikopf
- hartkodierte Texte
- Metrik-Grenzwerte (auch Member je Klasse, Zeilen je Unit, Units im uses)
- öffentliche Felder (freiwillig, die Korrektur kapselt sie)
- globale Variablen im interface (freiwillig)
- Namen:
  - lokale Namen, die ein Feld oder eine Property verdecken (aus VCL oder RTL geerbte nur, wo sie gemeint sein könnten, etwa ein `Left`, das nur zugewiesen wird; die Korrektur nimmt die Präfixe des Projekts)
  - Namen ohne das Präfix der Namenskonvention (freiwillig: lokale Variablen `m`, nicht öffentliche Felder `F`, Parameter `A`, Konstanten `c`; Präfixe aus `atlas.json` oder `naming` in `.atlas`; die Korrektur benennt Deklaration und Verwendungen um, still bei Interface-Implementierungen)
- `if`, das nur `True` oder `False` zuweist
- `UpperCase(A) = UpperCase(B)` statt `SameText`
- Zahlen ohne Namen
- zu lange Zeilen (freiwillig; über 1023 Zeichen immer eine Warnung, über 4095 ein Fehler wie F2069, #1383)
- auskommentierter Code (die Korrektur entfernt ihn)
- Geldbeträge als `Double` statt `Currency` (freiwillig)
- lange `if`-Ketten über denselben String (freiwillig, Korrektur `case IndexStr`)
- public- und published-Methoden, -Konstanten und -Properties, die kein Projekt der Projektgruppe verwendet (projektweit über den Symbolindex; still bei Packages und Bibliotheken, während der Index lädt und bei RTTI, Interfaces und Formularbindungen)
- alte Sammlungen:
  - ungenerische `TList`/`TObjectList`, die mit Cast gelesen werden, statt `TList<T>` (freiwillig; die Korrektur stellt die Liste auf `TList<T>` um)
  - ebenso `TStack`/`TQueue`/`TObjectStack`/`TObjectQueue` aus Contnrs (freiwillig; die Korrektur stellt auf `TStack<T>` usw. um, Warteschlangen mit `Enqueue`/`Dequeue`, Objektstapel mit `Create(False)`, damit die Besitzregel gleich bleibt)
- verbotene Symbole aus `atlas.json` (`forbidden-symbol`, freiwillig):
  - Routinen, Typen, Konstanten, Felder, Properties, Aufzählungswerte oder Bezeichner
  - mit Meldung, Ersatz als Korrektur, Schweregrad und Units je Eintrag
  - aufgelöst über die Namensauflösung (eine eigene Methode `Writeln` bleibt still)
  - auf der Seite Prüfregeln als Tabelle
- überflüssige Typumwandlungen wie `TStringList(FZeilen)` bei gleichem Typ oder `TObject(FStrom).Free` (Korrektur entfernt die Umwandlung)
- überflüssiges `inherited`:
  - überschreibende Methoden, die nur `inherited` aufrufen (Korrektur entfernt Deklaration und Rumpf)
  - ein bloßes `inherited;` in einer neuen Methode, die kein Vorfahr kennt (vergessenes `override`?, Korrektur entfernt den Aufruf)
- ein bloßes `Exit;` am Ende einer Routine und ein bloßes `Continue;` am Ende eines Schleifenrumpfs (Korrektur entfernt es; still in `try`-Blöcken und bei bedingten Direktiven)
- lange `if … else if`-Ketten, die denselben Ausdruck mit Konstanten vergleichen (freiwillig, Option `min`; die Korrektur wandelt in `case` um)

### Toter Code und Zyklen (#64)

- zirkuläre Unit-Referenzen mit vollständigem Rundweg (`uses-cycle`; reine interface-Zyklen als Fehler wie F2047)
- Routinen, Konstanten, Variablen und Typen nur im implementation-Teil, die nirgends verwendet werden (`unused-declaration`)
- Units, die nur das Programm im uses nennt (`unused-unit`)
- dazu ungenutzte private und öffentliche Member samt öffentlicher Typen und globaler Variablen

Absichtlich Ungenutztes per `deadCode.keepAttributes` (z. B. `[Schnittstelle]`) und `deadCode.keepPatterns` (z. B. `Test*`).

### Performance

- `SetLength(A, Length(A) + 1)` in Schleifen (bei bekannter Anzahl setzt die Korrektur die Länge vor der Schleife)
- String-, Interface-, Array- und Record-Parameter ohne `const`, die die Routine nie verändert (optional; die Korrektur ergänzt `const` in Deklaration und Rumpf)

## Steuerung der Befunde

- **Konfidenz** (hoch, mittel, niedrig) je Treffer begrenzt den Schweregrad.
- **Profile** `standard`, `fast`, `strict`, `security`, `style` oder eigene in `atlas.json`.
- **Vererbung über Units hinweg (#1326):** Die Prüfregeln
  - sehen Überladungen und Properties der Vorfahren auch in anderen Units,
  - unterscheiden generische und einfache Typen gleichen Namens (`TFoo` und `TFoo<T>`),
  - übernehmen Typ und Zugriffe einer ohne Typ neu deklarierten Property
  - und lesen Prozedurtypen über mehrere Zeilen (`of object`, `reference to`) vollständig.
  - `Edit` ohne `Post` gilt nur noch für Datenmengen.
- **Unterdrücken** mit `// lsp-ignore: regel`, mit Meldung unbenutzter oder vertippter Unterdrückungen
- **Baseline** für Altprojekte: bekannte Treffer ausblenden, nur neue melden

## Weitere Prüfungen

- **Compilerprüfung nach dem Speichern** und Übernahme der Meldungen aus dem Reiter „Build“
- **Suchpfade und Defines prüfen** für das aktive Projekt (Karte auf der Atlas-Willkommensseite)
- **Linter ohne IDE:**
  - `AtlasServer.exe --check` für Pre-Commit-Hooks und CI
  - als Text, JSON oder SARIF für GitHub Code Scanning
  - auf Wunsch nur geänderte Dateien oder Zeilen (siehe [Linter-Modus](Kommandozeile.md#linter-modus))
  - `--format-check` und `--format-write` prüfen bzw. setzen die Formatregeln um

Jede Regel mit Beschreibung und Vorher-Nachher-Beispiel: [docs/Regeln.md](../../../docs/Regeln.md).
