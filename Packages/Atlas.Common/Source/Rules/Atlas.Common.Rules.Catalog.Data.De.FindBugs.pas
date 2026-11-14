unit Atlas.Common.Rules.Catalog.Data.De.FindBugs;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeFindBugs: array[0..581] of string = (
    '{',
    '      "id": "result-not-set",',
    '      "name": "Funktionsergebnis eventuell nicht gesetzt",',
    '      "description": "Ein Pfad durch die Funktion endet, ohne Result zuzuweisen. Der Aufrufer liest dann einen undefinierten Wert. Eine for-Schleife läuft sicher einmal, wenn beide Grenzen Zahlenliter' +
    'ale oder echte Konstanten der Unit sind (cVersuche = 3) und der Bereich nicht leer ist, wie Delphi es wertet."',
    '    },',
    '{',
    '      "id": "possibly-uninitialized",',
    '      "name": "Variable eventuell nicht initialisiert",',
    '      "description": "Eine lokale Variable wird auf einem Pfad gelesen, auf dem ihr nie ein Wert zugewiesen wurde."',
    '    },',
    '{',
    '      "id": "unreachable-code",',
    '      "name": "Unerreichbarer Code",',
    '      "description": "Eine Anweisung nach Exit, raise, Abort, Halt, Break, Continue oder goto wird nie ausgeführt. Meist ein Rest oder ein falsch gesetzter Sprung. Gemeldet wird nur die erste Anweisun' +
    'g eines unerreichbaren Abschnitts."',
    '    },',
    '{',
    '      "id": "duplicate-assignment",',
    '      "name": "Feld oder Property wird zweimal gesetzt",',
    '      "description": "Dasselbe Feld oder dieselbe Property (Panel.Left, Self.FWert, P^.X) bekommt zweimal hintereinander einen Wert, ohne dass dazwischen gelesen oder etwas aufgerufen wird; meist soll' +
    'te die zweite Zeile ein anderes Ziel haben (Left/Top). Dazwischen dürfen nur Zuweisungen an andere Objekte stehen, deren Werte nichts aufrufen und das Ziel nicht nennen; der zweite Wert darf das Ziel ' +
    'nicht lesen. Lokale Variablen deckt unused-assignment ab, Ziele mit Index oder Aufruf zählen nicht. Still beim Wechsel False/True (stößt oft etwas an, etwa Active), bei einer zweiten Zuweisung, die nu' +
    'r unter einer weiteren Bedingung übersetzt wird ({$IFDEF DEBUG}), bei verschiedenen Zweigen desselben {$IFDEF} und bei Properties aus allowProperties. Fehlt das Gegenstück (Left/Top, Width/Height …) i' +
    'n der Folge, nennt die Meldung es als Vermutung. Konfidenz hoch. Keine Schnellkorrektur; Sprung zur ersten Zuweisung.",',
    '      "options": [',
    '        {',
    '          "name": "allowProperties",',
    '          "description": "Properties, bei denen doppeltes Setzen gewollt sein kann (Setter mit Nebenwirkung), Muster mit * und ?."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "declared-not-implemented",',
    '      "name": "Deklariert, aber nicht implementiert",',
    '      "description": "Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065). E' +
    'inen Rumpf gleichen Namens mit anderem Kopf meldet stattdessen signature-mismatch."',
    '    },',
    '{',
    '      "id": "implemented-not-declared",',
    '      "name": "Implementiert, aber nicht deklariert",',
    '      "description": "Ein Methodenrumpf TFoo.Bar hat keine Deklaration dieses Namens im Typ. Eine gleichnamige Deklaration mit anderem Kopf meldet stattdessen signature-mismatch."',
    '    },',
    '{',
    '      "id": "destroy-without-override",',
    '      "name": "Destroy ohne override",',
    '      "description": "Ein destructor Destroy ist ohne override deklariert. Free ruft TObject.Destroy auf, dieser Destruktor läuft also nie."',
    '    },',
    '{',
    '      "id": "setter-recursion",',
    '      "name": "Setter oder Getter ruft sich selbst auf",',
    '      "description": "Ein Setter weist an die eigene Property zu (Name := Value in SetName) oder ein Getter liest sie (Result := Name in GetName). Das ergibt eine Endlosrekursion und einen Stapelüberl' +
    'auf zur Laufzeit; der Compiler schweigt. Schnellkorrektur: das Feld verwenden (das Feld aus der Property-Deklaration, sonst F und der Name, wenn die Klasse es hat). Früher recursive-property-accessor;' +
    ' Einstellungen und Unterdrückungen mit der alten Kennung wirken weiter."',
    '    },',
    '{',
    '      "id": "hides-virtual",',
    '      "name": "Methode verdeckt virtuelle Methode",',
    '      "description": "Eine Methode heißt wie eine virtuelle Methode eines Vorfahren, überschreibt sie aber weder noch führt sie sie neu ein (Compilerwarnung W1010)."',
    '    },',
    '{',
    '      "id": "virtual-instead-of-override",',
    '      "name": "virtual statt override",',
    '      "description": "Ein Nachfahre deklariert eine Methode als virtual, obwohl der Vorfahr schon eine virtuelle Methode mit derselben Signatur hat; das beginnt eine neue Kette statt zu überschreiben.' +
    '"',
    '    },',
    '{',
    '      "id": "captured-loop-variable",',
    '      "name": "Erfasste Schleifenvariable",',
    '      "description": "Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer' +
    ' for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert. Still, wenn die anonyme Methode die Variable selbst zuweist (Ereignisse, die einen Zustand fortschreiben).",',
    '      "options": [',
    '        {',
    '          "name": "deferredApis",',
    '          "description": "Weitere verzögerte APIs (zusätzlich zu TThread.Queue, TTask.Run u. a.)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "interface-guid",',
    '      "name": "Interface ohne GUID",',
    '      "description": "Ein Interface deklariert keine GUID. Supports, as und QueryInterface brauchen eine. Die Konfidenz ist hoch, wenn das Interface in derselben Datei damit verwendet wird, sonst nied' +
    'rig; mit einer solchen Verwendung meldet Delphi dort E2232 (wie E2232). Die Schnellkorrektur fügt eine neue GUID ein. Ein dispinterface ohne GUID übersetzt nicht; das meldet dispinterface-invalid."',
    '    },',
    '{',
    '      "id": "duplicate-interface-guid",',
    '      "name": "Zwei Interfaces mit derselben GUID",',
    '      "description": "Zwei Interfaces der Datei deklarieren dieselbe GUID, meist nach dem Kopieren einer Deklaration. Supports und as verwechseln sie dann. Die Schnellkorrektur erzeugt eine neue GUID.' +
    '"',
    '    },',
    '{',
    '      "id": "self-assignment",',
    '      "name": "Zuweisung an sich selbst",',
    '      "description": "Einer Variablen, einem Feld oder einer Property wird der eigene Wert zugewiesen. Gemeint ist meist ein anderer Wert, etwa ein Parameter oder ein anderes Feld. Verdeckt ein Parame' +
    'ter oder eine lokale Variable ein gleichnamiges Feld (Name := Name), bietet Atlas Self.Name := Name als Korrektur an."',
    '    },',
    '{',
    '      "id": "exception-not-raised",',
    '      "name": "Exception erzeugt, aber nicht ausgelöst",',
    '      "description": "Ein Exception-Objekt wird als eigene Anweisung erzeugt. Ohne raise passiert nichts, und das Objekt bleibt als Speicherleck zurück."',
    '    },',
    '{',
    '      "id": "assert-side-effect",',
    '      "name": "Assert mit Seiteneffekt",',
    '      "description": "Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den gan' +
    'zen Aufruf samt Seiteneffekt.",',
    '      "options": [',
    '        {',
    '          "name": "mutatingMethods",',
    '          "description": "Methoden, die ihr Objekt verändern."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "ifthen-side-effect",',
    '      "name": "IfThen wertet beide Zweige aus",',
    '      "description": "IfThen ist eine Funktion: Beide Zweige werden vor dem Aufruf ausgewertet. Ein Nil-Zugriff oder Funktionsaufruf im nicht gewählten Zweig passiert trotzdem. Hohe Konfidenz, wenn ei' +
    'n Zweig einen in der Bedingung geprüften Namen dereferenziert, mittlere bei einem Funktionsaufruf."',
    '    },',
    '{',
    '      "id": "int32-mul-overflow",',
    '      "name": "Int32-Multiplikation an Int64 zugewiesen",',
    '      "description": "Beide Operanden haben höchstens 32 Bit; das Produkt wird in 32 Bit gerechnet und läuft über, bevor es der Int64-Variablen zugewiesen wird. Einen Operanden nach Int64 umwandeln."',
    '    },',
    '{',
    '      "id": "sizeof-pointer",',
    '      "name": "SizeOf eines Zeigers in Move oder FillChar",',
    '      "description": "SizeOf eines Zeigers, Strings oder dynamischen Arrays ist die Größe des Verweises (4 oder 8 Byte), nicht die der Daten. Move und FillChar kopieren bzw. löschen dann zu wenig."',
    '    },',
    '{',
    '      "id": "char-to-pchar",',
    '      "name": "Char nach PChar umgewandelt",',
    '      "description": "PChar(C) mit einer Char-Variablen macht aus dem Zeichencode eine Adresse. Gemeint war ein String."',
    '    },',
    '{',
    '      "id": "unrelated-class-cast",',
    '      "name": "Harte Umwandlung zwischen nicht verwandten Klassen",',
    '      "description": "TButton(Obj) prüft nichts. Ist der statische Typ von Obj weder Vorfahr noch Nachfahr von TButton (z. B. TEdit oder TForm), liest der Zugriff Speicher eines Objekts mit anderem Au' +
    'fbau. Gemeldet wird nur, wenn beide Typen sicher bekannt sind, beide Vererbungsketten bis TObject bekannt sind und beide Deklarationen immer mit der Umwandlung übersetzt werden. Interfaces, Zeiger, Za' +
    'hlen, TObject als Quelle und Umwandlungen in oder aus Klassenreferenzen (class of) bleiben still, ebenso der Zugriffsklassen-Trick: Das Ziel und seine Vorfahren bis zu einem gemeinsamen Vorfahren dekl' +
    'arieren weder Felder noch neue virtuelle Methoden (THackControl = class(TControl)), der Aufbau ist also derselbe. Sicherheit hoch. Korrektur: (Obj as TButton) prüft den Typ zur Laufzeit.",',
    '      "options": [',
    '        {',
    '          "name": "allowTypes",',
    '          "description": "Typen, die absichtlich hart umgewandelt werden: ein Typname (als Quelle oder Ziel) oder ein Paar \"Quelle=Ziel\"."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "first-char-address",',
    '      "name": "Adresse des ersten Zeichens über S[1]",',
    '      "description": "@S[1] und PChar(@S[1]) lösen bei leerem String mit {$R+} einen Bereichsfehler aus, ohne Bereichsprüfung ergibt sich nil oder Müll. Außerdem erzwingt der Indexzugriff eine eindeut' +
    'ige Kopie (UniqueString). PChar(S) und Pointer(S) sind auch für leere Strings sicher. Gilt für string, UnicodeString, WideString, AnsiString, RawByteString und UTF8String, auch S[Low(S)]; ShortString,' +
    ' Arrays und andere Indizes bleiben still. Gemeldet wird nur, wenn der Typ von S sicher bekannt ist. Sicherheit hoch. Korrektur bei const-Parametern: durch PChar(S) ersetzen (PAnsiChar bei AnsiString-T' +
    'ypen), ein umgebendes PChar(…), PAnsiChar(…), PWideChar(…), PByte(…) oder Pointer(…) wird als Ganzes ersetzt. Bei anderen Strings kann der Zeiger zum Schreiben dienen, dann ist die eigene Kopie gewoll' +
    't; dort gibt es keine Korrektur, die Meldung nennt UniqueString(S)."',
    '    },',
    '{',
    '      "id": "float-equality",',
    '      "name": "Gleitkommavergleich mit = oder <>",',
    '      "description": "Gleitkommawerte sind nach Berechnungen selten exakt gleich. Mit SameValue aus System.Math und einer Toleranz vergleichen. Vergleiche mit 0 werden nicht gemeldet."',
    '    },',
    '{',
    '      "id": "constructor-on-instance",',
    '      "name": "Konstruktor auf einer Instanz aufgerufen",',
    '      "description": "Create wird auf einer Variablen statt auf der Klasse aufgerufen. Das legt kein neues Objekt an; mit nicht zugewiesener Variable stürzt es ab. Klassenreferenzen (class of …) werde' +
    'n nicht gemeldet."',
    '    },',
    '{',
    '      "id": "format-args",',
    '      "name": "Formatstring passt nicht zu den Argumenten",',
    '      "description": "Format, FmtStr, FormatBuf, StrFmt, StrLFmt, WideFormat, WideFmtStr, Exception.CreateFmt bzw. CreateFmtHelp und TStringBuilder.AppendFormat mit bekanntem Formatstring (Literal, mi' +
    't + verbundene Literale, const oder resourcestring der Datei bzw. des Index), dessen Platzhalter nicht zur Argumentliste [...] passen: ungültiger Platzhalter (%q, ''%'' bzw. ''%5'' am Ende, %0: ohne Typbu' +
    'chstaben), weniger Argumente als Platzhalter oder ein Argument vom falschen Typ: %d %u %x nur Ganzzahlen, %e %f %g %n %m nur Gleitkommazahlen, %s Strings, Zeichen und Variants, %p Zeiger und Objekte, ' +
    'ein * für Breite bzw. Genauigkeit eine Ganzzahl; Variants passen überall. Boolean und Aufzählungswerte werden bei jedem Typbuchstaben gemeldet, mit Ord(...) bzw. BoolToStr(..., True) als Hinweis. All ' +
    'das löst zur Laufzeit EConvertError aus. Ein Argument hinter dem letzten verwendeten wird mit mittlerer Sicherheit gemeldet (nur ohne Index im Formatstring), es wird nie ausgegeben. Typen werden nur g' +
    'eprüft, wenn sie sicher bekannt sind; Formatstrings aus Variablen, Index * und Bereiche bleiben still. Eigene Routinen namens Format bleiben still, wenn die Namensauflösung sie findet. Teilt die Zerle' +
    'gung der Formatstrings mit format-without-settings. Keine Korrektur. Sicherheit hoch.",',
    '      "options": [',
    '        {',
    '          "name": "formatMethods",',
    '          "description": "Weitere Routinen mit Formatstring und folgender Argumentliste array of const, z. B. \"TLogger.LogFmt\" oder \"Protokoll\". Mit Punkt zählt ohne Namensauflösung der Methodenna' +
    'me hinter einem beliebigen Qualifizierer."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unresolved-identifier",',
    '      "name": "Nicht deklarierter Bezeichner",',
    '      "description": "Ein Bezeichner in einer Anweisung ist weder in der Unit noch in den eingebundenen Units deklariert (wie Compilerfehler E2003). Geprüft beim Tippen, ohne Compiler; with-Blöcke, as' +
    'm und anonyme Methoden werden übersprungen. Alte object-Syntax: In New(P, Init) und Dispose(P, Done) ist das zweite Argument ein Konstruktor bzw. Destruktor des object-Typs hinter P; fehlt er dort, me' +
    'ldet die Regel wie E2601 bzw. E2602, Fail außerhalb eines Konstruktors wie E2078."',
    '    },',
    '{',
    '      "id": "type-used-before-declaration",',
    '      "name": "Typ vor seiner Deklaration benutzt",',
    '      "description": "Eine Klasse, ein Interface, ein Record oder ein anderer Typ wird in einer Typdeklaration (Feld, Parameter, Ergebnis, Property, generisches Argument, class of) benutzt, ist aber e' +
    'rst weiter unten im selben Gültigkeitsbereich deklariert (wie Compilerfehler E2003). Vorfahren, Aliase und Zeigertypen werden nicht gemeldet, ebenso wenig class of auf eine Klasse weiter unten im selb' +
    'en type-Block (das übersetzt dcc) und ein Name, der weiter unten nur als Alias des gleichnamigen Typs einer anderen Unit steht (TX = UnitY.TX: davor gilt UnitY.TX aus uses). Schnellkorrekturen: Forwar' +
    'd-Deklaration am Anfang des type-Blocks ergänzen, type-Blöcke zusammenlegen (const-, var- und label-Abschnitte dazwischen wandern vor den ersten Block) oder einen Record vor seinen ersten Verwender ve' +
    'rschieben; ohne sichere Korrektur nennt die Meldung den Grund."',
    '    },',
    '{',
    '      "id": "field-not-freed",',
    '      "name": "Feld erzeugt, aber nie freigegeben",',
    '      "description": "Ein Objektfeld, das der Konstruktor (oder eine von ihm aufgerufene private Methode) mit TKlasse.Create erzeugt, wird in der Klasse nirgends freigegeben (kein Free, FreeAndNil, De' +
    'stroy oder DisposeOf): ein Speicherleck. Ausgenommen sind Komponenten mit einem Owner ungleich nil, Interface- und Record-Felder sowie die Klassen aus der Option ignoreTypes; TObjectList- und TObjectD' +
    'ictionary-Felder sind normale Felder. Konfidenz mittel. Schnellkorrekturen: das Feld im Destruktor freigeben oder alle eigenen Objekte der Klasse freigeben; ein fehlender Destruktor wird mit override ' +
    'und inherited angelegt. Die Freigaben stehen vor inherited in umgekehrter Erzeugungsreihenfolge, als Free oder FreeAndNil (refactoring.freeFieldsStyle). Bis #918 hieß die Regel owned-field-not-freed; ' +
    'Einstellungen und Unterdrückungen mit dieser Kennung wirken weiter.",',
    '      "options": [',
    '        {',
    '          "name": "ignoreTypes",',
    '          "description": "Klassen, die anderswo freigegeben werden; generische Typen treffen ohne Typparameter."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "owned-field-free-unclear",',
    '      "name": "Unklar, ob ein erzeugtes Feld freigegeben werden muss",',
    '      "description": "Ein im Konstruktor erzeugtes, nicht freigegebenes Objektfeld wird auch zurückgegeben (Result := FFeld, Exit(FFeld)), an eine Property eines anderen Objekts oder an dessen Add…, I' +
    'nsert…, Register…, Attach…, Push oder Enqueue übergeben, ohne Create zugewiesen oder ist über eine Property (write FFeld) schreibbar. Ob die Klasse das Objekt noch besitzt, entscheidet der Entwickler;' +
    ' deshalb gibt es keine Schnellkorrektur. Still bleibt die Regel, wenn der Empfänger seine Elemente besitzt: ein Feld vom Typ TObjectList, TObjectStack, TObjectQueue oder TComponentList, das nicht mit ' +
    'False erzeugt wird, oder ein Feld, dessen Klasse (aus der Datei oder dem Index) eine solche Liste für den Elementtyp hält. Felder vom Typ TArray<T> sind dynamische Arrays und werden nie gemeldet."',
    '    },',
    '{',
    '      "id": "operator-precedence",',
    '      "name": "Vorrang von not übersehen",',
    '      "description": "In Pascal bindet not stärker als in und Vergleiche: not X in Menge heißt (not X) in Menge, not A = B heißt (not A) = B, bei Ganzzahlen wird not bitweise. Die Regel meldet diese F' +
    'ormen, wenn der deklarierte Typ des Operanden zeigt, dass es nicht gemeint sein kann (kein Boolean). Schnellkorrektur: Klammern setzen, not (X in Menge)."',
    '    },',
    '{',
    '      "id": "empty-statement",',
    '      "name": "Leere Anweisung nach then, do oder else",',
    '      "description": "Ein Semikolon direkt nach then, do oder else beendet die Anweisung: Die folgende Zeile läuft dann immer bzw. die Schleife dreht leer. Ein leerer Block begin … end nach then, do o' +
    'der else wird ebenfalls gemeldet, außer er enthält einen erklärenden Kommentar (Option allowCommented). Ein Semikolon direkt vor end, until, except oder finally ändert nichts und bleibt unbeanstandet.' +
    ' Schnellkorrektur: Semikolon entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "allowCommented",',
    '          "description": "begin { absichtlich leer } end nicht melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "loop-off-by-one",',
    '      "name": "Schleife läuft einen Schritt zu weit",',
    '      "description": "for I := 0 to Liste.Count oder to Length(A) über nullbasierte Listen und Arrays greift im letzten Durchlauf hinter das Ende, wenn der Rumpf Liste[I] bzw. A[I] liest. Bei einsbasi' +
    'erten Strings umgekehrt: S[0] (Delphi meldet E2157) und for I := 0 to Length(S) greifen vor das erste Zeichen; {$ZEROBASEDSTRINGS ON} wird beachtet. Schnellkorrektur: - 1 ergänzen bzw. High(A) verwend' +
    'en, bei Strings Low(S) und High(S). Die Option countNames nennt die Namen, die eine Anzahl liefern.",',
    '      "options": [',
    '        {',
    '          "name": "countNames",',
    '          "description": "Namen, die eine Anzahl liefern (Property wie Count oder Funktion wie Length)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "collection-modified-in-loop",',
    '      "name": "Liste in der eigenen Schleife verändert",',
    '      "description": "Delete, Remove, Add oder eine andere Methode aus der Option mutatingMethods wird auf der Liste aufgerufen, über die die Schleife gerade vorwärts per Index oder mit for … in läuft' +
    '. Vorwärts überspringt Delete das nächste Element und läuft über das Ende, Add wird nicht mehr durchlaufen und Insert liefert dasselbe Element zweimal; mit for … in wirft die RTL eine Exception. Ein B' +
    'reak oder Exit ohne Bedingung nach dem Aufruf im selben Block beendet die Schleife und bleibt still (ein Break in einer inneren Schleife zählt nicht), downto-Schleifen ebenso. Schnellkorrektur bei Ind' +
    'exschleifen: rückwärts mit downto; bei for … in die Elemente sammeln und die Liste nach der Schleife ändern.",',
    '      "options": [',
    '        {',
    '          "name": "mutatingMethods",',
    '          "description": "Methoden, die die Liste verändern."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "use-after-free",',
    '      "name": "Objekt nach Free weiter benutzt",',
    '      "description": "Nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) oder Dispose(X) wird X ohne neue Zuweisung wieder benutzt: Methode, Feld, Index oder X^, with X, nach Free auch Assigned(X) (im' +
    'mer True) oder ein zweites Free. Die Regel folgt dem Datenfluss der Routine; eine Zuweisung an X, die Übergabe von X an eine Routine, @X und nach FreeAndNil eine Abfrage auf nil beenden den Weg, Wege ' +
    'nur über eine mögliche Ausnahme bleiben aus. Konfidenz hoch, wenn Freigabe und Zugriff im selben Block nacheinander stehen, sonst mittel. Keine automatische Korrektur; die Aktion springt zur Freigabe.' +
    '"',
    '    },',
    '{',
    '      "id": "deref-before-nil-check",',
    '      "name": "Erst benutzt, dann auf nil geprüft",',
    '      "description": "X wird dereferenziert (X.Feld, X.Methode, X^) und erst danach mit Assigned(X), X <> nil oder X = nil geprüft. Entweder ist die Prüfung überflüssig oder der Zugriff davor kann kna' +
    'llen. Gemeldet wird nur, wenn jeder Weg zur Prüfung durch den Zugriff führt und X vorher nicht geprüft wurde; eine neue Zuweisung, FreeAndNil(X), die Übergabe von X oder eines seiner Felder oder Eleme' +
    'nte (X.Feld, X[I]) an eine Routine und bei Feldern und globalen Variablen jeder Aufruf dazwischen beenden den Weg. Konfidenz mittel. Ist die Prüfung ein if ohne else direkt nach dem Zugriff im selben ' +
    'Block, zieht die Schnellkorrektur den Zugriff hinein."',
    '    },',
    '{',
    '      "id": "field-free-without-nil",',
    '      "name": "Feld freigegeben, Verweis bleibt stehen",',
    '      "description": "FFeld.Free in einer Methode außerhalb des Destruktors, und ein Weg zum Ende der Methode setzt das Feld nicht neu. Ein späterer Zugriff oder ein zweites Free trifft freigegebenen ' +
    'Speicher. Neu setzt eine Zuweisung oder der Aufruf einer Methode derselben Klasse, die das Feld zuweist. Felder sind die der Klassendeklaration in der Unit. Ausgenommen sind Destruktoren, Methoden mit' +
    ' [TearDown] oder [TearDownFixture], Methoden, die nur aus diesen aufgerufen werden, und die Methoden aus der Option ignoreMethods. Konfidenz mittel. Schnellkorrektur: FreeAndNil(FFeld).",',
    '      "options": [',
    '        {',
    '          "name": "ignoreMethods",',
    '          "description": "Methoden, in denen Free ohne nil erlaubt ist."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "missing-inherited",',
    '      "name": "Konstruktor oder Destruktor ohne inherited",',
    '      "description": "Ein Konstruktor oder ein override von Destroy, AfterConstruction oder BeforeDestruction ruft inherited nicht auf, in jeder Klasse, deren Vorfahr nicht TObject ist. Konstruktoren ' +
    'werden nur gemeldet, wenn ein Vorfahr einen eigenen Konstruktor deklariert (Datei, Index oder bekannte RTL-/VCL-Klasse) und der Konstruktor keinen anderen Konstruktor derselben Klasse aufruft. Bei Kom' +
    'ponenten meldet Destroy nur component-missing-inherited. Konfidenz hoch. Schnellkorrektur: inherited; am Ende von Destroy und BeforeDestruction, am Anfang von Konstruktoren und AfterConstruction; ein ' +
    'Konstruktor mit Parametern ohne override bekommt inherited Create;.",',
    '      "options": [',
    '        {',
    '          "name": "methods",',
    '          "description": "Geprüfte Methoden; Create steht für alle Konstruktoren, deren Name mit Create beginnt."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "inherited-order",',
    '      "name": "inherited an der falschen Stelle",',
    '      "description": "Im Destruktor steht inherited (inherited; bzw. inherited Destroy) als Anweisung des Rumpfs vor einer späteren Anweisung, die ein Feld der Klasse selbst freigibt (F.Free, F.Dispos' +
    'eOf, FreeAndNil(F), auch mit Self.): Der Vorfahr kann noch virtuelle Methoden aufrufen, die das Feld brauchen. Klassen, in deren Kette eine Klasse mit Thread im Namen steht, bleiben still, denn TThrea' +
    'd.Destroy wartet auf Execute und gehört dort an den Anfang. Im Konstruktor greifen die Anweisungen vor inherited auf ein Feld oder eine Property eines Vorfahren zu (aufgelöst über Datei und Index; eig' +
    'ene Felder, Parameter und lokale Variablen zählen nicht), solange der Vorfahr noch nicht angelegt ist. missing-inherited meldet fehlendes inherited, diese Regel die Reihenfolge. Konfidenz mittel. Schn' +
    'ellkorrektur: inherited an das Ende des Destruktors bzw. den Anfang des Konstruktors verschieben; nicht, wenn die Argumente von inherited Create vorher gesetzte lokale Variablen verwenden."',
    '    },',
    '{',
    '      "id": "inherited-wrong-method",',
    '      "name": "inherited ruft eine andere Methode",',
    '      "description": "In der überschriebenen Methode Speichern steht inherited Laden(…) statt inherited Speichern(…), meist nach Kopieren einer Methode. Es zählen nur Aufrufe (inherited Name als Anwei' +
    'sung oder mit Klammern); inherited Caption ohne Klammern kann eine Property sein. Still in Konstruktoren (inherited Create(nil), CreateNew), in Methoden ohne override und wenn die Methode auch sich se' +
    'lbst im Vorfahren aufruft (inherited; bzw. inherited Speichern), denn dann ist der andere Aufruf gewollt. Paare aus der Option allowed bleiben still. Konfidenz hoch. Schnellkorrektur: den Namen durch ' +
    'den eigenen ersetzen, wenn die Zahl der Argumente zu ihren Parametern passt.",',
    '      "options": [',
    '        {',
    '          "name": "allowed",',
    '          "description": "Erlaubte Paare \"Methode>geerbte Methode\", Muster mit * und ?, z. B. \"Speichern>Pruefen\"."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "getter-side-effect",',
    '      "name": "Getter verändert den Zustand",',
    '      "description": "Die read-Methode einer Property weist Feldern oder Properties des eigenen Objekts zu (FAbrufe, Self.FWert, auch geerbte Felder), ruft Inc/Dec/Include/Exclude darauf auf oder über' +
    'gibt ein neu angelegtes Objekt an eine Methode eines Felds (FListe.Add(TEintrag.Create)). Der Debugger wertet Getter beim Anzeigen aus und ändert so den Zustand. Lazy-Initialisierung ist erlaubt: Ein ' +
    'umschließendes if prüft etwas, das sein Zweig zuweist (if FListe = nil then FListe := …, if Result = nil then … FListe := Result, if not FGeladen then … FGeladen := True). Still bei lokalen Variablen ' +
    'mit dem Namen eines Felds, Result, Methoden ohne Property und anonymen Methoden. Eine Meldung je Getter und Feld. Konfidenz mittel. Keine Schnellkorrektur.",',
    '      "options": [',
    '        {',
    '          "name": "allowLazyInit",',
    '          "description": "Lazy-Initialisierung im Getter erlauben (if FListe = nil then FListe := …)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "equals-without-gethashcode",',
    '      "name": "Equals ohne GetHashCode",',
    '      "description": "Eine Klasse überschreibt Equals, aber nicht GetHashCode (oder umgekehrt). In TDictionary und THashSet mit Standard-Comparer finden gleiche Objekte sich dann nicht. Still, wenn ei' +
    'n Vorfahr das Gegenstück überschreibt, wenn die Vorfahrenkette nicht vollständig bekannt ist und bei Equals ohne override. Gilt ebenso für Records der Datei mit class operator Equal, die als Schlüssel' +
    ' von TDictionary, TObjectDictionary, THashSet oder TMultiMap ohne Comparer dienen (Create ohne Argumente oder nur mit Konstanten wie Kapazität oder Besitz): Der Standard-Comparer vergleicht Records By' +
    'te für Byte, was nur bei Feldern vom Typ string, Variant, Gleitkomma, Interface oder TArray falsch ist; Records mit nur ordinalen Feldern bleiben still. Konfidenz hoch. Schnellkorrektur für Klassen: G' +
    'etHashCode hinter Equals deklarieren und hinter dem Rumpf von Equals mit THashBobJenkins über die eigenen Felder umsetzen, die Equals vergleicht (ohne Groß-/Kleinschreibung über LowerCase, wenn Equals' +
    ' SameText nutzt), System.Hash in uses ergänzen."',
    '    },',
    '{',
    '      "id": "destroy-called-directly",',
    '      "name": "Destroy statt Free aufgerufen",',
    '      "description": "Obj.Destroy wird direkt als Anweisung aufgerufen. Ist Obj nil, knallt der Aufruf; Free prüft vorher auf nil und ist der übliche Weg, ein Objekt freizugeben. inherited Destroy und' +
    ' Aufrufe eines Destruktors mit Argumenten sind ausgenommen. Konfidenz hoch. Schnellkorrektur: aus Destroy wird Free."',
    '    },',
    '{',
    '      "id": "managed-type-raw-memory",',
    '      "name": "FillChar, Move oder GetMem auf verwaltete Typen",',
    '      "description": "FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem oder FreeMem auf eine Variable, deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält (Records, statis' +
    'che Arrays und Aliasse werden in der Datei und im Index aufgelöst). Referenzzähler werden überschrieben oder übergangen: Lecks, doppelte Freigabe, Zugriffsverletzungen. Geprüft werden nur einfache Var' +
    'iablen (X, @X, P^); Array-Elemente wie S[1] und Typen, die sich nicht auflösen lassen, bleiben still. Konfidenz hoch. Schnellkorrekturen: aus FillChar(X, SizeOf(X), 0) wird X := Default(T), aus Move(A' +
    ', B, SizeOf(T)) wird B := A, aus GetMem(P, SizeOf(T)) wird New(P) und aus FreeMem(P) wird Dispose(P); sonst helfen Initialize und Finalize."',
    '    },',
    '{',
    '      "id": "pchar-of-temporary",',
    '      "name": "PChar auf einen temporären String",',
    '      "description": "PChar (PWideChar, PAnsiChar) eines temporären Strings, etwa einer Verkettung mit einem String (S + ''.bak'') oder eines Funktionsergebnisses (IntToStr(N)), wird in einer Variablen,' +
    ' einem Feld oder Result gemerkt oder an PostMessage, PostThreadMessage, SendNotifyMessage oder SendMessageCallback übergeben (auch hinter LPARAM(…)). Der temporäre String wird nach der Anweisung freig' +
    'egeben, der Zeiger zeigt dann ins Leere. Die Übergabe an einen gewöhnlichen Aufruf wie CopyFile ist in Ordnung. Konfidenz hoch. Schnellkorrektur für lokale Variablen: das Zwischenergebnis in eine Inli' +
    'ne-String-Variable legen."',
    '    },',
    '{',
    '      "id": "out-param-read",',
    '      "name": "out-Parameter gelesen, bevor er gesetzt ist",',
    '      "description": "Ein out-Parameter wird auf einem Weg durch den Kontrollfluss gelesen, bevor die Routine ihn setzt. Bei verwalteten Typen (string, Interfaces, dynamische Arrays, Variant) hat der ' +
    'Aufrufer ihn schon geleert, der alte Wert ist weg; bei anderen Typen ist der Wert undefiniert. Gemeint war meist var. Verwendungen, denen der Kontrollflussgraph nicht folgen kann (Übergabe an eine Rou' +
    'tine, Setzen eines Felds, @Param), bleiben still. Konfidenz hoch. Schnellkorrektur: aus out wird var in Implementierung und Deklaration."',
    '    },',
    '{',
    '      "id": "noreturn-returns",',
    '      "name": "noreturn-Routine kann normal zurückkehren",',
    '      "description": "Eine mit noreturn markierte Routine (ab Delphi 13) darf nur über raise, Abort, Halt, RunError oder den Aufruf einer anderen noreturn-Routine enden. Erreicht ein Weg das Ende des ' +
    'Rumpfs oder ein Exit, kehrt sie normal zurück; der Compiler hat den Code nach dem Aufruf weggelassen, das Verhalten ist undefiniert. Die Direktive zählt an der Implementierung und an der Deklaration (' +
    'interface, Klasse). Aufrufe, deren Ziel weder die Datei, die Standardroutinen noch der Symbolindex kennt, könnten selbst noreturn sein und beenden den Weg ebenfalls; gemeldet werden also nur Wege aus ' +
    'bekannten Anweisungen. Unvollständiger Kontrollfluss (asm, Syntaxfehler) bleibt still. Exit wird an der Anweisung gemeldet, das Ende des Rumpfs am Routinennamen. Konfidenz hoch. Keine Schnellkorrektur' +
    '."',
    '    },',
    '{',
    '      "id": "stringlist-unsorted",',
    '      "name": "Find oder Duplicates auf einer unsortierten TStringList",',
    '      "description": "Find auf einer TStringList oder THashedStringList, die in der Unit erzeugt, aber nie sortiert wird: Find sucht binär und liefert auf einer unsortierten Liste falsche Ergebnisse. ' +
    'Ebenso wirkt Duplicates := dupIgnore oder dupError nur bei sortierten Listen. Als sortiert gelten Sorted := True (oder jeder Wert außer False), Sort, CustomSort, Create(Duplicates, True, ...) und with' +
    ' Liste do. Eine Liste, die an eine Routine übergeben oder einer anderen Variablen zugewiesen wird, bleibt still. Lokale Variablen gelten je Routine, Felder in der ganzen Unit. Konfidenz mittel. Schnel' +
    'lkorrekturen: Sorted := True nach dem Erzeugen (nicht, wenn die Liste Insert, Move oder Exchange benutzt, die bei sortierten Listen eine Ausnahme auslösen) und bei if Liste.Find(S, I) then die Form I ' +
    ':= Liste.IndexOf(S) mit if I >= 0."',
    '    },',
    '{',
    '      "id": "writeln-in-gui-app",',
    '      "name": "Writeln in einem Programm ohne Konsole",',
    '      "description": "Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem Programm ohne Konsole: zur Laufzeit löst Writeln EInOutError aus (E/A-Fehler 105), Readln E/A-Fehler ' +
    '104. Die Anwendungsart kommt aus DCC_ConsoleTarget der .dproj und {$APPTYPE CONSOLE} der .dpr (auch in {$IFDEF}); Units werden nur geprüft, wenn sie zum geladenen Projekt gehören, eine .dpr ohne Proje' +
    'kt für sich. Bibliotheken und Packages bleiben still. Ausgenommen sind Aufrufe mit einer Textdatei als erstem Argument, Aufrufe unter if IsConsole, gleichnamige Routinen der Unit und Read/Write in Met' +
    'hoden (TStream.Read). Konfidenz hoch. Schnellkorrektur für Write und Writeln: Ersatz durch OutputDebugString(PChar(...)) und Winapi.Windows im uses; Zahlen und Boolean über IntToStr, FloatToStr und Bo' +
    'olToStr. Die Option replacement setzt ein anderes Ziel, z. B. Log.Info oder Logger.Log(TLogLevel.Info, %s). Keine Korrektur bei Breitenangaben (X:5) oder Argumenten unbekannten Typs.",',
    '      "options": [',
    '        {',
    '          "name": "replacement",',
    '          "description": "Ersatz für Write und Writeln in der Schnellkorrektur; %s steht für den Text."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "duplicate-condition",',
    '      "name": "Doppelte Bedingung oder gleiche Zweige",',
    '      "description": "Dieselbe Bedingung zweimal in einer if … else if-Kette (der spätere Zweig wird nie erreicht), gleiche then- und else-Zweige, derselbe Operand zweimal in einer and-, or- oder xor-' +
    'Kette und Vergleiche eines Ausdrucks mit sich selbst (X = X, X < X). Meist ein Kopierfehler. Verglichen werden die Token ohne Leerraum, Kommentare und Groß-/Kleinschreibung. Ketten mit Aufrufen, die Z' +
    'ustand ändern können (alles außer SameText, Length, Assigned, Pos und ähnlichen reinen Funktionen, dazu Read, Next, Pop, Random …), bleiben still, ebenso Gleitkomma-Vergleiche mit sich selbst (NaN-Prü' +
    'fung X <> X) und Vergleiche über Klassenmitglieder wie TFoo.Shared = TFoo.Shared. Konfidenz hoch. Keine Schnellkorrektur; die Aktion springt zum ersten Vorkommen."',
    '    },',
    '{',
    '      "id": "case-missing-enum-value",',
    '      "name": "case über Aufzählung ohne alle Werte",',
    '      "description": "Ein case über einen Aufzählungstyp ohne else deckt nicht alle Werte ab; ein später ergänzter Wert fällt still durch. Die Meldung nennt die fehlenden Werte. Den Typ des Selektors ' +
    '(Variable, Parameter, Feld oder Kette A.B) liefert die Namensauflösung, die Werte der Index bzw. die Unit selbst; Aliase werden verfolgt. Bereiche (bsNeu..bsBezahlt) und Listen zählen als vorhanden. S' +
    'elektoren mit Aufrufen, Ganzzahlen und unbekannte Typen bleiben still. Mit der Option requireElse wird auch ein case mit else gemeldet. Konfidenz hoch. Schnellkorrektur „Fehlende Werte ergänzen (n)“ e' +
    'rgänzt leere Zweige in Deklarationsreihenfolge vor else bzw. end, mit Typpräfix, wenn die Marken einen tragen ({$SCOPEDENUMS ON}).",',
    '      "options": [',
    '        {',
    '          "name": "requireElse",',
    '          "description": "Auch case-Anweisungen mit else melden, wenn Werte fehlen."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "pair-without-finally",',
    '      "name": "Paarige Aufrufe ohne try/finally",',
    '      "description": "Verallgemeinert lock-without-finally (dessen Sperrpaare dort bleiben) auf andere Paare: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (auch in if Fin' +
    'dFirst(...) = 0 then begin ... end), Reset, Rewrite oder Append/CloseFile, GetMem oder AllocMem/FreeMem und Screen.Cursor := ... mit einem späteren Screen.Cursor := .... Gemeldet wird, wenn das Schlie' +
    'ßen später ungeschützt in derselben Anweisungsliste steht und mindestens eine Anweisung dazwischen liegt; eine Exception dort lässt den Zustand hängen. Beide Aufrufe müssen denselben Empfänger bzw. da' +
    'sselbe Argument haben. Überlappende Paare meldet die Regel zusammen. Konfidenz hoch. Schnellkorrektur: die Anweisungen dazwischen in try/finally mit den schließenden Aufrufen einschließen, wenn diese ' +
    'direkt aufeinander folgen. Die Option pairs ergänzt eigene Paare.",',
    '      "options": [',
    '        {',
    '          "name": "pairs",',
    '          "description": "Weitere Paare als [{\"open\": \"Einfrieren\", \"close\": \"Auftauen\"}], wahlweise mit openArg/closeArg."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unchecked-conversion",',
    '      "name": "Umwandlung einer Benutzereingabe ohne Prüfung",',
    '      "description": "StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime oder StrToCurr direkt auf einer Benutzereingabe (Edit.Text, Grid.Cells[...], Memo.Lines[...], auch in Trim) außerhalb d' +
    'es try-Teils eines try/except. Eine Fehleingabe löst EConvertError mit englischer Meldung aus. try/finally gilt nicht als Schutz. Konfidenz mittel. Schnellkorrektur für X := StrToInt(Edit.Text); als e' +
    'igene Anweisung, wenn X eine Variable oder ein Feld des passenden Typs ist: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create(''X ist keine Zahl''). format-without-settings meldet zusätzl' +
    'ich landesabhängige Umwandlungen ohne TFormatSettings. Die Optionen functions und sources wählen die geprüften Umwandlungen und die Eigenschaften, die als Eingabe gelten.",',
    '      "options": [',
    '        {',
    '          "name": "functions",',
    '          "description": "Geprüfte Umwandlungen."',
    '        },',
    '        {',
    '          "name": "sources",',
    '          "description": "Eigenschaften, die als Benutzereingabe gelten."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "dictionary-get-without-check",',
    '      "name": "Dictionary-Zugriff ohne Prüfung des Schlüssels",',
    '      "description": "Dict[Key] bzw. Dict.Items[Key] wird auf einem TDictionary oder TObjectDictionary (auch über einen Typalias der Datei) gelesen, obwohl weder ContainsKey noch TryGetValue denselben' +
    ' Schlüssel vorher in der Routine geprüft hat. Still bleibt die Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue, TryAdd, Dict[K] := ...) oder der Schlüssel aus Keys bzw. ' +
    'den Paaren stammt (for K in Dict.Keys, Namen := Dict.Keys.ToArray, for Pair in Dict mit K := Pair.Key). Fehlt der Schlüssel, folgt EListError. Konfidenz mittel. Schnellkorrektur für X := Dict[Key]; al' +
    's eigene Anweisung, wenn X eine Variable vom Wertetyp ist: if not Dict.TryGetValue(Key, X) then X := 0 (bzw. '''', False, Default(T))."',
    '    },',
    '{',
    '      "id": "event-call-without-assigned",',
    '      "name": "Ereignis ohne Assigned-Prüfung aufgerufen",',
    '      "description": "FOnChange(Self) oder OnChange(Self) wird in einer Methode der Klasse aufgerufen, ohne dass Assigned(FOnChange) oder FOnChange <> nil den Aufruf schützt: Ohne Handler folgt eine Z' +
    'ugriffsverletzung. Ereignisse sind Felder und Properties der Klasse mit Methodenzeiger- oder Referenztyp (procedure … of object, reference to …, TNotifyEvent, TProc/TFunc, Typen auf Event, prozedurale' +
    ' Typen der Unit oder des Index). Schutz: der then-Zweig einer Bedingung mit Assigned (auch while), der else-Zweig von not Assigned, \"Assigned(F) and\" vor dem Aufruf oder \"if not Assigned(F) then Ex' +
    'it/raise\" davor, auch über einen Merker oder eine Methode der Klasse ohne Parameter, deren Result Assigned(F) enthält. Still bleiben Felder, die ein Konstruktor mit einem Wert belegt (eingereichte Ab' +
    'hängigkeiten wie FReadText := AReadText), Properties darauf und gleichnamige lokale Namen. Sicherheit hoch. Korrektur: den Aufruf in \"if Assigned(F) then\" einschließen, wenn er als eigene Anweisung ' +
    'in einem Block steht."',
    '    },',
    '{',
    '      "id": "owned-item-freed",',
    '      "name": "Element einer besitzenden Liste zusätzlich freigegeben",',
    '      "description": "Ein Element einer TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True) oder eines TObjectDictionary mit doOwnsValues wird mit Free, FreeAndNil, Destroy oder DisposeOf freigegeb' +
    'en, direkt (Liste[I].Free, Liste.Items[I].Free) oder über eine Variable aus Liste[I], Liste.First/Last oder einer for-in-Schleife über die Liste bzw. Dictionary.Values. Die Liste gibt das Element selb' +
    'st frei: bei Delete, Remove, Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben, also doppelt. Besitzend ist eine Liste, wenn die Unit sie so erzeugt (TObjectList ohne False, TObjectDic' +
    'tionary mit doOwnsValues) oder ohne Erzeugung als TObjectList deklariert, und kein OwnsObjects := False folgt. Extract in derselben Routine lässt die Regel schweigen. Sicherheit hoch. Korrekturen: Fre' +
    'e entfernen (die ganze Schleife, wenn sie nur freigibt), Delete bzw. Remove statt Free, Extract statt Remove."',
    '    },',
    '{',
    '      "id": "create-without-assignment",',
    '      "name": "Objekt erzeugt und sofort verloren",',
    '      "description": "TStringList.Create; als eigene Anweisung: Das Objekt wird erzeugt, aber nirgends gespeichert und nie freigegeben (Speicherleck). Still bleiben Komponenten mit Owner (erstes Argum' +
    'ent Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit einem Argument ungleich nil), Threads (geben sich mit FreeOnTerminate selbst frei), Records, unbekannte Klassen mit Argumenten' +
    ' und Klassen aus selfRegistering. Sicherheit hoch. Korrektur: Zuweisung an eine neue lokale Variable, die folgenden Anweisungen des Blocks in try/finally mit Free.",',
    '      "options": [',
    '        {',
    '          "name": "selfRegistering",',
    '          "description": "Klassen, die sich im Konstruktor selbst registrieren, als Muster mit * und ?; Create als Anweisung bleibt für sie still."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "raw-memory-leak",',
    '      "name": "GetMem oder New ohne Freigabe",',
    '      "description": "Eine lokale Variable erhält Speicher über GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc oder StrNew, die Routine gibt ihn aber nie mit FreeMem, FreeMemory, Dispose, StrD' +
    'ispose oder ReallocMem(P, 0) frei, und der Zeiger verlässt die Routine nicht: weder zurückgegeben (Result, Exit) noch einer anderen Variablen oder einem Feld zugewiesen, nicht über seine Adresse (@P) ' +
    'weitergegeben, keiner Methode übergeben, die ihn behält (Add, Insert, Push …), nicht von einer anonymen Methode eingefangen und nicht in einer lokalen Routine benutzt. Zum Lesen oder Füllen weitergebe' +
    'n (Pruefsumme(P, N), Strom.ReadBuffer(P^, N)) ist erlaubt; eine Routine mit Free, Frei, Release, Dispose, Destroy oder Dealloc im Namen gilt als Freigabe. Eine Freigabe ohne try/finally meldet pair-wi' +
    'thout-finally. Konfidenz mittel. Schnellkorrektur: die folgenden Anweisungen des Blocks in try … finally mit der passenden Freigabe einschließen."',
    '    },',
    '{',
    '      "id": "local-object-not-freed",',
    '      "name": "Lokales Objekt nie freigegeben",',
    '      "description": "Eine lokale Variable (auch Inline-Variable) erhält T.Create(…) einer Klasse ohne Owner, die Routine gibt das Objekt aber nie frei, und es verlässt die Routine nicht: weder zurück' +
    'gegeben (Result, Exit) noch etwas anderem zugewiesen (Feld, andere Variable, Listenelement), nicht als Argument weitergegeben (außer an Routinen, die nur lesen: Assign, AddStrings, CopyFrom, LoadFromS' +
    'tream, SaveToStream, IndexOf, Contains, Equals), nicht mit raise ausgelöst, nicht mit as umgewandelt, nicht mit @, in einem Mengen- oder Array-Konstruktor oder mit with benutzt, kein Parent oder Owner' +
    ' gesetzt, nicht von einer anonymen Methode eingefangen und nicht in einer lokalen Routine benutzt. Free, Destroy, DisposeOf, Release, FreeAndNil und Routinen mit Free, Release, Destroy, Dispose oder F' +
    'rei im Namen gelten als Freigabe; Show, Close, Start, Resume, Run und Execute als Übergabe (Formular mit caFree, Thread). Still bleiben Interface-Variablen, Records und dynamische Arrays (TPoint.Creat' +
    'e, TArray<string>.Create), Threads, Komponenten mit Owner und unbekannte Klassen mit Argumenten (wie create-without-assignment); Routinen mit asm oder with bleiben still. Konfidenz hoch, wenn die Vorf' +
    'ahren der Klasse bis TObject bekannt sind, sonst mittel. Schnellkorrektur: die folgenden Anweisungen des Blocks in try … finally mit Free einschließen."',
    '    },',
    '{',
    '      "id": "created-result-not-freed",',
    '      "name": "Neues Objekt aus einer Funktion nie freigegeben",',
    '      "description": "Eine lokale Variable erhält das Ergebnis einer Funktion, die immer ein neues Objekt liefert, und die Routine gibt es weder frei noch weiter (gleiche Regeln wie local-object-not-f' +
    'reed). Eine Funktion derselben Datei zählt, wenn ihr Ergebnistyp eine Klasse ist (kein Record aus einer Klassenfunktion Create), jede Zuweisung an Result T.Create(…) ohne Owner ist, Result sonst nur ü' +
    'ber seine Mitglieder benutzt oder freigegeben wird (Aufräumen im except) und nie weitergeht, und jedes Exit(…) ebenfalls ein Objekt erzeugt; gleichnamige Überladungen müssen das alle erfüllen. Erkannt' +
    ' wird sie unqualifiziert, über Self oder über einen Typnamen aufgerufen; Methoden anderer Objekte kennt die Regel nur aus der Option factories. Konfidenz mittel. Schnellkorrektur: die folgenden Anweis' +
    'ungen des Blocks in try … finally mit Free einschließen.",',
    '      "options": [',
    '        {',
    '          "name": "factories",',
    '          "description": "Weitere Funktionen, die immer ein neues Objekt liefern, das dem Aufrufer gehört, als Name, Klasse.Name, Objekt.Name oder Unit.Name."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "anonymous-method-self-cycle",',
    '      "name": "Anonyme Methode hält ihren eigenen Rahmen fest",',
    '      "description": "Eine lokale Variable (auch Inline-Variable) erhält eine anonyme Methode der Routine, und eine anonyme Methode derselben Routine fängt diese Variable ein (auch die anonyme Methode' +
    ' selbst, bei Rekursion). Alle anonymen Methoden einer Routine teilen einen Rahmen, der die eingefangenen Variablen hält; über die Variable verweist der Rahmen dann auf sich selbst und wird nie freigeg' +
    'eben, samt allem, was er eingefangen hat. Still, wenn die Variable in der Routine auf nil gesetzt wird. Konfidenz hoch. Keine Schnellkorrektur: die Methodenreferenz in einer eigenen Routine bauen (der' +
    'en Rahmen hält die Variable nicht) oder die Variable vor dem Ende der Routine auf nil setzen."',
    '    },',
    '{',
    '      "id": "event-handler-not-unhooked",',
    '      "name": "Ereignis eines fremden Objekts nicht zurückgesetzt",',
    '      "description": "Eine Methode weist eine Methode der eigenen Klasse einem Ereignis OnXyz eines fremden Objekts zu (Fremd.OnChange := Handler oder Self.Handler), und weder Destroy, BeforeDestructi' +
    'on, Notification noch Release (Abmelden einer Klasse mit Klassenmethoden) der Klasse setzen dieses Ereignis zurück. Fremd heißt: Parameter der Methode oder Feld, das eine Methode der Klasse aus einem ' +
    'Parameter übernimmt (FFeld := AQuelle), das die Klasse nie selbst erzeugt und das nicht im published-Teil steht (Komponenten der Formulardatei gehören dem Formular). Lebt das fremde Objekt länger, ruf' +
    't es die Methode eines freigegebenen Objekts auf. Still bei eigenen Ereignissen (OnChange := …), Handlern, die keine Methoden der Klasse sind, und Anweisungen in with-Blöcken oder anonymen Methoden. K' +
    'onfidenz mittel. Schnellkorrektur bei Feldern: if Assigned(FFeld) then FFeld.OnXyz := nil; am Anfang des Destruktors der Datei einfügen."',
    '    },',
    '{',
    '      "id": "interface-object-mixed",',
    '      "name": "Objekt mit Referenzzählung als Objekt und als Interface benutzt",',
    '      "description": "Eine lokale Objektvariable einer Klasse mit Referenzzählung (Nachfahre von TInterfacedObject, keine Klasse der Kette deklariert _AddRef oder _Release selbst) wird als Interface w' +
    'eitergegeben und zusätzlich mit Free, FreeAndNil, Destroy oder DisposeOf freigegeben: Der letzte Interface-Verweis gibt das Objekt ein zweites Mal frei. Oder sie wird nur vorübergehend als Interface w' +
    'eitergegeben (X as IFoo oder IFoo(X) als Argument einer Routine; eine Methode eines anderen Objekts wie Liste.Add(X as IFoo) behält den Verweis meist und zählt wie eine Interface-Variable) und danach ' +
    'wieder über die Objektvariable benutzt: Fällt der vorübergehende Verweis weg, sinkt der Zähler auf 0, und das Objekt ist schon freigegeben. Als Interface weitergegeben heißt: einer Interface-Variablen' +
    ' der Routine oder Result einer Funktion mit Interface-Ergebnis zugewiesen, oder mit as bzw. einer Typumwandlung zu einem Interface gemacht. Still, wenn eine Interface-Variable das Objekt für die Routi' +
    'ne hält, und nachdem die Variable ein neues Objekt erhalten hat. Inline-Variablen und stille Umwandlungen an Interface-Parameter prüft die Regel nicht. Konfidenz mittel. Keine Schnellkorrektur: das Ob' +
    'jekt nur in einer Interface-Variablen halten."',
    '    },',
    '{',
    '      "id": "interface-cycle-without-weak",',
    '      "name": "Interfaces halten sich gegenseitig ohne [weak]",',
    '      "description": "Zwei Klassen der Datei halten sich über Interface-Felder gegenseitig fest: Ein Feld der Klasse X zeigt auf ein Interface, das die Klasse Y implementiert (direkt, als TList<IFoo>,' +
    ' IList<IFoo>, TArray<IFoo> oder array of IFoo), und ein Feld von Y auf ein Interface von X. Innerhalb einer Klasse (Baum mit Rückverweis) muss eine Seite eine Liste und die andere ein einzelnes Feld s' +
    'ein; einzelne Felder derselben Klasse allein (verkettete Liste) bleiben still. Keines der Felder darf [weak] oder [unsafe] sein. Dann wird keines der Objekte freigegeben, weil jedes den Zähler des and' +
    'eren über 0 hält. Gemeldet an beiden Feldern. Experimentell: nur im Profil strict oder wenn in rules eingeschaltet. Klassen anderer Units bleiben außen vor. Konfidenz mittel. Schnellkorrektur: [weak] ' +
    'am einzelnen Feld, wenn die andere Seite eine Liste ist (Rückverweis des Kinds)."',
    '    },',
    '{',
    '      "id": "stringlist-objects-leak",',
    '      "name": "Objekte in einer TStringList ohne Besitz",',
    '      "description": "AddObject oder InsertObject legt ein neu erzeugtes Objekt (T.Create(…) direkt oder eine so erzeugte lokale Variable, die sonst nur gelesen wird) in eine TStringList (oder THashed' +
    'StringList), die die Unit ohne OwnsObjects erzeugt, oder in die Items eines Felds vom Typ TListBox, TComboBox, TCheckListBox, TComboBoxEx oder TColorListBox; niemand gibt diese Objekte frei. Besitzend' +
    ' ist eine Liste mit TStringList.Create(True) oder OwnsObjects := True. Still, wenn eine Routine der Unit Liste.Objects[…] liest und etwas freigibt, wenn die Liste weitergegeben wird (ObjekteFreigeben(' +
    'Liste), anderswo zugewiesen), wenn das Objekt einen Owner hat (Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit Argument) und bei Listen, die nicht in der Unit erzeugt werden. Kon' +
    'fidenz mittel. Schnellkorrektur: TStringList.Create(True) (auch statt Create(False)), bei anderen Konstruktoren OwnsObjects := True nach der Erzeugung; für Items von Steuerelementen keine."',
    '    },',
    '{',
    '      "id": "message-handler-without-inherited",',
    '      "name": "Message-Handler ohne inherited",',
    '      "description": "Eine Methode mit message WM_… oder CM_… ruft weder inherited noch DefaultHandler (bzw. DefWindowProc, CallWindowProc) auf. Die Standardbehandlung der VCL bzw. von Windows fällt w' +
    'eg: kein Neuausrichten bei WM_SIZE, kein Schließen bei WM_CLOSE, kein Zeichnen bei WM_PAINT. Die Meldung nennt für gängige Nachrichten die Folge. Still bleiben Klassen ohne Vorfahr, Nachrichten aus sw' +
    'allow (Vorgabe WM_ERASEBKGND) und Handler, die Msg.Result selbst setzen (bewusste Antwort wie MA_NOACTIVATE). Sicherheit mittel. Korrektur: inherited; am Anfang einfügen.",',
    '      "options": [',
    '        {',
    '          "name": "swallow",',
    '          "description": "Nachrichten, die ohne inherited behandelt werden dürfen; ersetzt die Vorgabe."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "string-index-base",',
    '      "name": "String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen",',
    '      "description": "Die klassischen String-Routinen zählen ab 1: Copy(S, 0, N) und Insert(T, S, 0) wirken nur zufällig wie 1, Delete(S, 0, N) löscht nichts. Der String muss bekannt sein: deklarierte' +
    'r Typ in der Datei, Literal oder .Text/.Caption; dynamische Arrays (ab 0) bleiben still. Pos, PosEx und AnsiPos liefern 0 bei keinem Treffer: Pos(…) > -1, >= 0 und <> -1 sind immer wahr, = -1 und < 0 ' +
    'nie. Umgekehrt übersieht S.IndexOf(…) > 0 bzw. >= 1 den Treffer am Anfang, < 1 bzw. <= 0 zählt ihn als nicht gefunden (Sicherheit mittel; LastIndexOf bleibt still, dort heißt > 0 meist „nicht am Anfan' +
    'g“). Sicherheit hoch für Delete und Pos. Korrektur: Startwert 1 bzw. der richtige Vergleich (> 0, = 0, >= 0, < 0)."',
    '    },',
    '{',
    '      "id": "delimited-text-without-strict",',
    '      "name": "DelimitedText ohne StrictDelimiter",',
    '      "description": "Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass StrictDelimiter gesetzt wird: DelimitedText trennt dann auch an Leerzeichen, ''Max Muster;Berlin' +
    ''' ergibt drei statt zwei Einträge. Bei Feldern zählt StrictDelimiter in der ganzen Unit (oft im Konstruktor); StrictDelimiter := False ist bewusst und bleibt still, ebenso DelimitedText ohne eigenen D' +
    'elimiter. Sicherheit hoch. Korrektur: StrictDelimiter := True; vor der Zuweisung einfügen."',
    '    },',
    '{',
    '      "id": "self-as-interface-in-constructor",',
    '      "name": "Self während der Konstruktion als Interface weitergegeben",',
    '      "description": "Self wird als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann. Gemeldet werden nur zwei echte Fehlerfälle: (1) Eine Klasse mit eigener Refere' +
    'nzzählung (ein _Release in der Klassenkette gibt das Objekt frei, keine Klasse überschreibt NewInstance, die Kette ist bis TObject bekannt) gibt Self im Konstruktor oder in AfterConstruction als Inter' +
    'face weiter: Der Zähler steigt von 0 auf 1 und fällt wieder auf 0, das Objekt wird freigegeben, bevor die Konstruktion endet. (2) Ein Nachfahr von TInterfacedObject gibt Self in AfterConstruction nach' +
    ' inherited als Interface weiter: inherited AfterConstruction hat den Schutzzähler aus NewInstance schon abgebaut. Im Konstruktor eines TInterfacedObject-Nachfahren ist Self geschützt, die Regel bleibt' +
    ' still. Als Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Sicherheit hoch. Kor' +
    'rektur in Fall 2: die Anweisung vor inherited verschieben."',
    '    },',
    '{',
    '      "id": "unchecked-enum-cast",',
    '      "name": "Zahl ungeprüft in Aufzählung umgewandelt",',
    '      "description": "TStatus(N) mit einem Aufzählungstyp aus der Datei oder dem Index, wenn N aus einem Aufruf der Option sources stammt (FieldByName, ReadInteger, AsInteger, StrToInt): direkt im Arg' +
    'ument oder über eine Variable, die zwischen Zuweisung und Umwandlung nicht gelesen (geprüft) wird. Ein Wert außerhalb des Bereichs ergibt einen ungültigen Aufzählungswert, der in case durchfällt. Ensu' +
    'reRange, Min oder Max im Argument gelten als Prüfung; Konstanten, Rechnungen und unbekannte Typen bleiben still. Bei Aufzählungen mit eigenen Ordinalwerten nennt die Meldung den Bereich als Ord(Low(T)' +
    ')..Ord(High(T)). Sicherheit mittel. Korrektur bei direkter Quelle in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise EConvertError davor, System.Math in uses.",',
    '      "options": [',
    '        {',
    '          "name": "sources",',
    '          "description": "Aufrufe, deren Ergebnis als ungeprüft gilt."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "createprocess-readonly-commandline",',
    '      "name": "CreateProcess mit unveränderlicher Befehlszeile",',
    '      "description": "CreateProcess (CreateProcessW) und CreateProcessAsUser schreiben in den Puffer von lpCommandLine. Ein PChar auf Speicher, der nicht beschreibbar ist, führt zu einer Zugriffsverle' +
    'tzung. Gemeldet wird PChar(…)/PWideChar(…) auf: ein String-Literal oder eine Konstante; eine Verkettung aus genau einem Literal und einem Wert (ist der Wert leer, liefert die RTL das Literal selbst); ' +
    'eine lokale String-Variable, deren letzte Zuweisung vor dem Aufruf eines davon ist, ohne UniqueString danach; einen String-Parameter (Sicherheit mittel, der Aufrufer kann ein Literal übergeben). Funkt' +
    'ionsergebnisse wie Format und Verkettungen aus mehreren Teilen sind beschreibbare Heap-Strings und bleiben still, ebenso CreateProcessA, das die Befehlszeile selbst kopiert. Korrektur: Befehlszeile in' +
    ' eine lokale Variable kopieren und UniqueString aufrufen; bei einer Variablen UniqueString vor der Anweisung. In Schleifenbedingungen keine Korrektur."',
    '    },',
    '{',
    '      "id": "form-access-before-create",',
    '      "name": "Zugriff auf ein Formular, das noch nicht erzeugt ist",',
    '      "description": "Der Konstruktor, AfterConstruction oder der OnCreate-Handler eines automatisch erzeugten Formulars bzw. Datenmoduls benutzt die globale Variable eines anderen Formulars, das die ' +
    '.dpr erst danach mit Application.CreateForm erzeugt. Die Variable ist dort noch nil. Die Reihenfolge stammt aus der .dpr des Projekts, zu dem die Unit gehört; der OnCreate-Handler aus der Formulardate' +
    'i (ohne Eintrag FormCreate bzw. DataModuleCreate). Still, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil), selbst zuweist, mit CreateForm erzeugt oder einen gleichnamigen lokalen Nam' +
    'en deklariert, und bei Formularen, die nicht automatisch erzeugt werden. Jede Variable wird je Routine einmal gemeldet. Sicherheit mittel. Keine Korrektur: die Reihenfolge in der .dpr ändern oder den ' +
    'Zugriff nach OnShow verlegen."',
    '    },',
    '{',
    '      "id": "destructor-not-nil-safe",',
    '      "name": "Destruktor benutzt Felder, die nil sein können",',
    '      "description": "Wirft ein Konstruktor, ruft Delphi sofort den Destruktor auf, obwohl noch nicht alle Felder angelegt sind. Gemeldet wird ein Zugriff im Destruktor (oder in einer privaten Methode' +
    ', die nur der Destruktor aufruft) auf ein Feld wie FZeilen.Clear, FDatei.Position oder FZeilen[0], wenn ein Konstruktor der Klasse das Feld (TKlasse.Create) erst nach einem Aufruf anlegt, der werfen k' +
    'ann, oder nur auf manchen Wegen. Die Zugriffsverletzung verdeckt dann die eigentliche Exception. Free, FreeAndNil, DisposeOf und Zugriffe nach Assigned(FFeld) bzw. FFeld <> nil sind nil-sicher; Before' +
    'Destruction läuft auf diesem Weg nicht. Konstruktoren von RTL-Klassen, die höchstens EOutOfMemory werfen (TStringList.Create, TObjectList<T>.Create(True)), inherited Create und Supports zählen nicht a' +
    'ls werfend. Konfidenz hoch. Schnellkorrektur: if Assigned(FFeld) then vor die Anweisung setzen. Mit onlyAfterRaisingCode aus zählt jedes im Konstruktor angelegte Feld.",',
    '      "options": [',
    '        {',
    '          "name": "onlyAfterRaisingCode",',
    '          "description": "Nur melden, wenn der Konstruktor vor dem Anlegen des Felds etwas aufruft, das eine Exception werfen kann."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "handle-leak",',
    '      "name": "Windows-Handle wird nicht geschlossen",',
    '      "description": "Ein Windows-Handle in einer lokalen Variablen wird auf einem Weg zum Ende der Routine nicht mit dem passenden Gegenstück geschlossen: CreateFile, CreateEvent, CreateMutex, OpenPr' +
    'ocess, CreateProcess (hProcess, hThread) und CreateToolhelp32Snapshot mit CloseHandle, FindFirstFile mit FindClose, RegOpenKeyEx/RegCreateKeyEx mit RegCloseKey, LoadLibrary mit FreeLibrary, GetDC mit ' +
    'ReleaseDC, CreatePen/CreateBrush/CreateFont/CreateBitmap mit DeleteObject, CreateCompatibleDC mit DeleteDC und weitere. Zurückgeben, Speichern in einem Feld oder einer globalen Variablen, Übergabe an ' +
    'eine unbekannte Routine, Speichern in einem Array ([H] in einem Ausdruck) und Verwenden in einer anonymen Methode gelten als Weitergabe. Zweige, in denen eine if-Prüfung sagt, dass das Öffnen misslang' +
    ' (H = 0, H = INVALID_HANDLE_VALUE, RegOpenKeyEx(...) <> ERROR_SUCCESS), und Ausnahmewege (siehe pair-without-finally) zählen nicht. Die Option pairs ergänzt eigene Paare. Konfidenz mittel. Schnellkorr' +
    'ektur, wenn das Handle nie geschlossen wird: die Anweisungen nach dem Öffnen in try … finally mit dem Schließen einschließen bzw. das Schließen anhängen, wenn das Öffnen die letzte Anweisung ist.",',
    '      "options": [',
    '        {',
    '          "name": "pairs",',
    '          "description": "Zusätzliche Paare aus Öffnen und Schließen als \"Oeffnen>Schliessen\" oder {\"open\": …, \"close\": …}; die Öffnen-Funktion liefert das Handle, die Schließen-Prozedur bekommt' +
    ' es als einziges Argument."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "component-interface-dangling",',
    '      "name": "Komponente als Interface gespeichert und freigegeben",',
    '      "description": "Ein Nachfahr von TComponent (Formular, Frame, Datenmodul, eigene Komponente) implementiert ein Interface, aber TComponent zählt keine Referenzen. Gemeldet wird das Speichern des ' +
    'Objekts als Interface in einem Feld, einer globalen Variablen oder einer Liste (FAnsicht as IBeobachter an Bus.Anmelden, FListe.Add, Register, Subscribe …, Zuweisung an ein Feld oder eine globale Vari' +
    'able, Add in TList<IFoo>/TInterfaceList), wenn dieselbe Unit das Objekt freigibt (Free, Release, DisposeOf, FreeAndNil) und es nirgends abmeldet: FreeNotification auf dem Objekt, ein anderer Aufruf am' +
    ' selben Empfänger mit dem Objekt als Argument (Abmelden, Remove, Unsubscribe …), Clear oder eine weitere Zuweisung an dasselbe Feld. Nach der Freigabe zeigt das gespeicherte Interface ins Leere. Still' +
    ' bei Klassen mit eigenem _Release und wenn die Kette der Vorfahren an einer unbekannten Klasse endet. Ebenso gemeldet, ohne Schnellkorrektur: Nachfahren von TInterfacedObject, die so gespeichert und z' +
    'usätzlich mit Free freigegeben werden; das gespeicherte Interface hält dann ein freigegebenes Objekt, und eine Abmeldung davor gäbe es schon frei. Konfidenz mittel. Schnellkorrektur: Abmeldung vor der' +
    ' ersten Freigabe einfügen (Empfänger.Abmelden(…), wenn der Typ des Empfängers das Gegenstück hat, bzw. Feld := nil).",',
    '      "options": [',
    '        {',
    '          "name": "componentClasses",',
    '          "description": "Basisklassen ohne Referenzzählung; mit TComponent zählen auch die bekannten VCL- und FMX-Klassen (TForm, TFrame, TDataModule …)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "constant-condition",',
    '      "name": "Bedingung ist immer gleich",',
    '      "description": "Die Bedingung von if, while oder until steht fest: True, False, Vergleiche von Zahlen und untypisierte Konstanten der Datei, auch über and, or, xor und not (X or True ist immer w' +
    'ahr, X and False immer falsch). Der Zweig ist toter Code oder läuft immer. while True do und repeat … until False gelten als gewollte Endlosschleifen (deren Ausgang prüft infinite-loop). Konstanten au' +
    's switchConstants, Konstanten in einem Zweig von {$IF…} und Konstanten aus anderen Units gelten als unbekannt. Korrektur bei if: toten Zweig bzw. die Bedingung entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "switchConstants",',
    '          "description": "Konstanten, die bewusst als Schalter dienen; Bedingungen darauf werden nicht gemeldet."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "infinite-loop",',
    '      "name": "Schleife ohne Ausgang",',
    '      "description": "while True do, repeat … until False oder eine andere Schleife, deren Bedingung sie nie beendet, ohne Ausgang im Rumpf: kein Break (ein Break in einer inneren Schleife verlässt nu' +
    'r diese), Exit, raise, goto, Halt, Abort oder RunError, kein Aufruf einer Routine der Datei, die eine Ausnahme auslöst oder das Programm beendet, und keine Prüfung von Terminated (Thread-Schleifen prü' +
    'ft thread-loop-without-terminated). Anonyme Methoden im Rumpf zählen nicht. Die Aktion springt zum Schleifenkopf."',
    '    },',
    '{',
    '      "id": "loop-condition-unchanged",',
    '      "name": "Schleifenbedingung ändert sich im Rumpf nie",',
    '      "description": "Keine Variable der while- bzw. until-Bedingung ändert sich im Rumpf: keine Zuweisung, kein Inc/Dec, kein Argument (möglicherweise var), kein Methoden- oder Mitgliedszugriff auf d' +
    'as Objekt der Bedingung, keine for-Schleife darüber. Typisch ist das vergessene Inc(I) oder Next. Gemeldet wird nur, wenn jede Variable der Bedingung eine lokale Variable oder ein Wertparameter der Ro' +
    'utine ist und mindestens eine direkt (nicht nur als X.Eigenschaft) vorkommt. Still bleiben Bedingungen mit Funktionsaufrufen, Feldern, globalen Variablen, var- und out-Parametern und Terminated, außer' +
    'dem Schleifen mit Ausgang (Break, Exit, raise …), Warteschleifen (Sleep, ProcessMessages …), with, Aufrufen lokaler Routinen und Variablen, die eine anonyme Methode erfasst. Änderungen über X[…] zähle' +
    'n nur, wenn die Bedingung X[…] liest."',
    '    },',
    '{',
    '      "id": "loop-runs-at-most-once",',
    '      "name": "Schleife läuft höchstens einmal",',
    '      "description": "Jeder Weg durch den Rumpf einer for-, for-in-, while- oder repeat-Schleife endet mit Exit, Break, raise, Halt, Abort, RunError, ExitProcess oder dem Aufruf einer Routine der Date' +
    'i, die eine Ausnahme auslöst; die Schleife läuft also höchstens einmal. Meist fehlt ein if vor dem Sprung, oder ein Continue war gemeint. Ein Weg zählt als Sprung bei if mit else und beiden Zweigen, c' +
    'ase mit else und allen Zweigen, try … finally mit try- oder finally-Teil und try … except mit try-Teil und jedem Behandler. Still bei Continue dieser Schleife, goto bzw. Marken und bedingten Direktive' +
    'n im Rumpf; ein Break innerer Schleifen zählt nicht. Ergänzt infinite-loop und loop-condition-unchanged. Keine Korrektur, die Absicht ist unklar; steht der Sprung direkt hinter einem if ohne else, fra' +
    'gt die Meldung, ob er in den if-Zweig gehört. Sicherheit hoch.",',
    '      "options": [',
    '        {',
    '          "name": "allowFirstElement",',
    '          "description": "for-in aus einfachen Anweisungen, das mit Exit bzw. Break endet (erstes Element holen), nicht melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unconditional-recursion",',
    '      "name": "Rekursion ohne Abbruch",',
    '      "description": "Eine Routine ruft sich auf jedem Pfad selbst auf, bevor sie zurückkehren kann: Es gibt keinen Pfad ohne Selbstaufruf und kein Exit oder raise davor. Ergebnis ist ein Stapelüberla' +
    'uf. Pfade ohne Aufruf sind: if ohne else bzw. case ohne else, der Rumpf von while und for, die rechte Seite von and/or, Zweige von if-Ausdrücken und anonyme Methoden. Getter und Setter der eigenen Pro' +
    'perty meldet setter-recursion; überladene Routinen bleiben still (der Aufruf kann eine andere Überladung treffen). Das Randsymbol aus #623 zeigt jede Rekursion."',
    '    },',
    '{',
    '      "id": "pos-arguments-swapped",',
    '      "name": "Argumente von Pos vertauscht",',
    '      "description": "Pos(Text, '';''): Pos, PosEx, AnsiPos, StartsText, StartsStr, EndsText und EndsStr (auch mit Ansi-Präfix) erwarten zuerst den gesuchten Teil, dann den Text; ContainsText und Contai' +
    'nsStr erwarten zuerst den Text. Gemeldet, wenn an der Stelle des Textes ein kurzes Literal steht (bis maxLiteralLength Zeichen, Vorgabe 3; '''' zählt als ein Zeichen, #9 ebenso) und an der Stelle des Te' +
    'ils sicher ein String: eine Variable oder ein Feld mit in der Datei deklariertem String-Typ, .Text oder .Caption, eine String-Funktion der RTL (Trim, UpperCase, LeftStr, Format …) oder eine Verkettung' +
    ' mit einem String-Teil. Zeichen bleiben still, weil Pos(C, '';,'') bewusst prüft, ob C einer der Trenner ist; ebenso unbekannte Typen, zwei Literale und Methoden anderer Objekte (Liste.Pos). Konfidenz m' +
    'ittel. Schnellkorrektur: Argumente in einer Änderung tauschen; Kommentare dazwischen bleiben.",',
    '      "options": [',
    '        {',
    '          "name": "maxLiteralLength",',
    '          "description": "Längstes Literal an der Stelle des Textes, das noch als vertauscht gilt."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "integer-division-to-float",',
    '      "name": "Ganzzahldivision an Gleitkommazahl",',
    '      "description": "Schnitt := Summe div Anzahl mit Schnitt: Double: div schneidet die Nachkommastellen ab, bevor zugewiesen wird. Ebenso Prozent := Teil div Gesamt * 100, Result einer Funktion mit ' +
    'Gleitkommaergebnis und var X: Double := A div B. Gesucht wird durch Klammern, Vorzeichen und + - * / hindurch, nicht in Aufrufen (Round(A div B)), Indizes, mod oder Vergleichen. Das Ziel muss eine Var' +
    'iable, ein Feld (auch Self.X) oder Result sein, deren Typ Single, Double, Extended, Real, Currency … in der Datei deklariert ist. TDateTime, TDate und TTime bleiben still (ganze Tage sind dort meist g' +
    'ewollt), ebenso Zuweisungen in with und Trunc(A) div Trunc(B) (auch Round, Floor, Ceil: ausdrücklich gewandelt, also gewollt ganzzahlig). Konfidenz hoch. Schnellkorrektur: div durch / ersetzen (gleich' +
    'er Vorrang)."',
    '    },',
    '{',
    '      "id": "ignored-result",',
    '      "name": "Ergebnis einer Funktion ohne Seiteneffekte verworfen",',
    '      "description": "Eine Funktion ohne Seiteneffekte steht als eigene Anweisung, ihr Ergebnis geht verloren: Trim(S); ändert S nicht, S.Replace(''a'', ''b''); auch nicht. Gemeldet werden die unten genan' +
    'nten Standardroutinen (auch mit Unit davor, SysUtils.Trim), Methoden von TStringHelper ohne Seiteneffekte, wenn der Empfänger sicher vom Typ string ist, und die Funktionen aus der Option pureFunctions' +
    '. Findet die Namensauflösung den Namen in einer Unit außerhalb der RTL oder deklariert die Datei selbst eine Routine dieses Namens (eigenes Trim mit var-Parameter), bleibt die Regel still, ebenso in w' +
    'ith-Blöcken. Routinen mit var- oder out-Parametern und Routinen, die bei falscher Eingabe absichtlich eine Exception werfen (StrToInt oder S.ToInteger als Prüfung), stehen nicht in der Liste. Konfiden' +
    'z hoch. Schnellkorrektur „Ergebnis zuweisen“: Liefert die Funktion den Typ ihres ersten Arguments bzw. des Helfer-Empfängers (Trim, StringReplace, Copy, S.Replace …) und ist dieser zuweisbar, wird dar' +
    'aus S := Trim(S); sonst eine neue Inline-Variable var Ergebnis := … (nur direkt in einem Block begin … end und ab Delphi 10.3). Standardroutinen je Unit: System: Abs, Assigned, Chr, Concat, Copy, Frac' +
    ', High, Int, Length, Low, Odd, Ord, Pos, Pred, Round, SizeOf, Sqr, Sqrt, StringOfChar, Succ, Trunc, UpCase; System.SysUtils: IntToStr, IntToHex, FloatToStr, CurrToStr, BoolToStr, Format, FormatFloat, ' +
    'QuotedStr, AnsiQuotedStr, Trim, TrimLeft, TrimRight, LowerCase, UpperCase, AnsiLowerCase, AnsiUpperCase, StringReplace, SameText, SameStr, CompareText, CompareStr, AnsiSameText, AnsiSameStr, AnsiCompa' +
    'reText, AnsiCompareStr, AnsiPos, StrToIntDef, StrToInt64Def, StrToFloatDef, StrToBoolDef, ExtractFileName, ExtractFileExt, ExtractFilePath, ExtractFileDir, ExtractFileDrive, ChangeFileExt, ChangeFileP' +
    'ath, IncludeTrailingPathDelimiter, ExcludeTrailingPathDelimiter, IncludeTrailingBackslash, ExcludeTrailingBackslash, AdjustLineBreaks, IsDelimiter, LastDelimiter, string.Join, string.Create, string.Fo' +
    'rmat, string.IsNullOrEmpty, string.IsNullOrWhiteSpace, string.Compare, string.CompareOrdinal, string.CompareText, string.LowerCase, string.UpperCase, string.EndsText; System.StrUtils: PosEx, ContainsT' +
    'ext, ContainsStr, StartsText, StartsStr, EndsText, EndsStr, MatchText, MatchStr, IndexText, IndexStr, LeftStr, RightStr, MidStr, ReplaceStr, ReplaceText, AnsiReplaceStr, AnsiReplaceText, AnsiContainsT' +
    'ext, AnsiStartsText, AnsiEndsText, DupeString, ReverseString, SplitString, IfThen; System.Math: Max, Min, Ceil, Floor, Power, IntPower, Sign, EnsureRange, InRange, SameValue, IsZero, RoundTo, SimpleRo' +
    'undTo, Log10, Log2; System.IOUtils: TPath.Combine, TPath.GetFileName, TPath.GetFileNameWithoutExtension, TPath.GetExtension, TPath.GetDirectoryName, TPath.ChangeExtension. TStringHelper: Trim, TrimLef' +
    't, TrimRight, TrimStart, TrimEnd, ToUpper, ToLower, ToUpperInvariant, ToLowerInvariant, Replace, Substring, PadLeft, PadRight, Insert, Remove, QuotedString, DeQuotedString, Contains, StartsWith, EndsW' +
    'ith, IndexOf, IndexOfAny, LastIndexOf, LastIndexOfAny, IsEmpty, Split, ToCharArray, Equals, CompareTo, CountChar, IsDelimiter, LastDelimiter, GetHashCode.",',
    '      "options": [',
    '        {',
    '          "name": "pureFunctions",',
    '          "description": "Weitere Funktionen ohne Seiteneffekte, die wie die Standardroutinen gemeldet werden, als Name, Klasse.Name oder Unit.Name."',
    '        }',
    '      ]',
    '    }');

implementation

end.
