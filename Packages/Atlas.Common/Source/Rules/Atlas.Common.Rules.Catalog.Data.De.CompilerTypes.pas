unit Atlas.Common.Rules.Catalog.Data.De.CompilerTypes;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeCompilerTypes: array[0..106] of string = (
    '{',
    '      "id": "assign-to-property-member",',
    '      "name": "Zuweisung an ein Feld eines Property-Records",',
    '      "description": "Zuweisung an ein Feld eines Records, den eine Property mit Getter, eine Default- oder Array-Property oder ein Funktionsergebnis nur als Kopie liefert (wie E2064): Die Zuweisung h' +
    'at keine Wirkung. Zuweisungen an untypisierte Konstanten meldet die Regel ebenso. Typen kommen aus der Namensauflösung; gemeldet wird nur bei sicher bekanntem Record-Typ. Liest die Property direkt ein' +
    ' Feld, schreibt Delphi in dieses Feld, und die Regel bleibt still. Korrektur bei einer Property mit write: über eine lokale Variable zuweisen und zurückschreiben; die Variable wird in der Routine dekl' +
    'ariert, die Unit ihres Typs in uses ergänzt."',
    '    },',
    '{',
    '      "id": "readonly-property-assigned",',
    '      "name": "Zuweisung an eine Property ohne write",',
    '      "description": "Zuweisung an eine Property ohne write (wie E2129) bzw. Lesen einer Property ohne read (wie E2130). Die Regel meldet nur, wenn die Namensauflösung die Property sicher findet; Neud' +
    'eklarationen ohne read und write (property Caption;) gelten als unbekannt. Korrekturen: Count := 0 wird Clear, wenn der Typ Clear hat; in einer Methode der deklarierenden Klasse das Feld hinter read z' +
    'uweisen; für eine Property dieser Datei den Setter anlegen und write ergänzen."',
    '    },',
    '{',
    '      "id": "untyped-pointer-refcount",',
    '      "name": "Untypisierter Zeiger umgeht die Referenzzählung",',
    '      "description": "Ein Interface wird über eine Typumwandlung nach Pointer zugewiesen (Pointer(FIntf) := P, wie W1070). Die Referenzzählung läuft dann nicht mit: das Objekt wird zu früh freigegeben' +
    ' oder nie. Die Regel meldet nur, wenn die Namensauflösung den Interface-Typ sicher kennt; Strings (string, AnsiString …) meldet sie ebenfalls, mit dem Zusatz „dcc meldet das nicht“, weil Delphi bei ih' +
    'nen nur unter NEXTGEN warnt. Felder mit [weak] oder [unsafe] bleiben still. Korrekturen für ein Interface-Feld dieser Datei mit Pointer(Y) oder nil rechts: das Feld mit [weak] bzw. [unsafe] auszeichne' +
    'n und ohne Pointer zuweisen."',
    '    },',
    '{',
    '      "id": "comparison-always-constant",',
    '      "name": "Vergleich immer wahr oder immer falsch",',
    '      "description": "Vergleich einer Variablen, eines Feldes, einer Property oder eines Funktionsergebnisses vom eingebauten Ganzzahltyp mit einer Konstanten außerhalb bzw. am Rand des Wertebereichs ' +
    '(wie W1021, W1022): Cardinal >= 0 ist immer wahr, Byte > 255 immer falsch. Ebenso case-Marken außerhalb des Bereichs des case-Ausdrucks (wie W1018); einzelne Marken, die auch mit anderem Vorzeichen ni' +
    'cht in die Breite des Typs passen, sind für dcc ein Fehler und meldet constant-expression-error (wie E1012). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit dem Vergleich über' +
    'setzt wird. NativeInt, LongInt und ihre vorzeichenlosen Gegenstücke gelten mit dem weitesten Bereich aller Plattformen; Teilbereichstypen meldet die Regel nicht. Length(…) < 0 und Length(…) >= 0 melde' +
    't sie ebenfalls, obwohl dcc dort nicht warnt; die Meldung sagt das dazu."',
    '    },',
    '{',
    '      "id": "case-selector-not-ordinal",',
    '      "name": "case oder for ohne ordinalen Typ",',
    '      "description": "case über einen nicht ordinalen Ausdruck (wie E2001): Strings, Gleitkommazahlen, Klassen und Interfaces; for-Schleife mit nicht ordinaler Zählvariable (wie E2032); case-Marken un' +
    'd Array-Grenzen, die Variablen, Felder, Properties, Parameter oder typisierte Konstanten statt Konstanten sind (wie E2026). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der' +
    ' Anweisung übersetzt wird. Korrektur bei Strings mit lauter String-Literalen als Marken: case IndexStr(S, […]) of mit den Positionen als Marken, System.StrUtils kommt in die uses."',
    '    },',
    '{',
    '      "id": "suspicious-string-pointer-cast",',
    '      "name": "Zeiger und Zeichenbreite eines Strings passen nicht zusammen",',
    '      "description": "PChar bzw. PWideChar auf einen AnsiString, RawByteString oder UTF8String und PAnsiChar auf einen string, UnicodeString oder WideString (wie W1044): Zeiger und Zeichenbreite passe' +
    'n nicht zusammen, typisch nach der Unicode-Umstellung; die API liest dann Datenmüll bzw. nur das erste Zeichen. Gemeldet wird nur bei sicher bekanntem Typ des Arguments, dessen Deklaration immer mit d' +
    'er Umwandlung übersetzt wird. string(PAnsiChar) wandelt korrekt um, ein Zeiger auf TBytes kann gewollt sein; beides meldet die Regel nicht. Korrekturen: eigene Variable mit passendem Stringtyp deklari' +
    'eren (PChar(Pfad) mit Pfad: AnsiString wird Pfad: string), string(…) bzw. AnsiString(…) um das Argument, passenden Zeigertyp verwenden."',
    '    },',
    '{',
    '      "id": "string-conversion",',
    '      "name": "Umwandlung zwischen Unicode- und ANSI-Strings",',
    '      "description": "Implizite und ausdrückliche Umwandlungen zwischen string, UnicodeString oder WideString auf der einen und AnsiString, RawByteString oder UTF8String auf der anderen Seite, wie die' +
    ' Compilerwarnungen: implizit in string (wie W1057) bzw. in AnsiString mit möglichem Datenverlust (wie W1058) bei Zuweisungen, Inline-Variablen mit Typ und Argumenten für Wert- und const-Parameter von ' +
    'Routinen ohne Überladungen; ausdrückliche Umwandlungen string(A) (wie W1059) und AnsiString(S) (wie W1060); eine Stringkonstante mit Zeichen, die die ANSI-Codepage nicht kennt, an einen AnsiString (wi' +
    'e W1058 und W1062); ein WideChar in einem Mengenausdruck aus Zeichenliteralen wie C in [''0''..''9''] (wie W1050); ein Zeichen eines string direkt ändern (S[1] := ''x'', wie W1068). Wie bei dcc meldet die R' +
    'egel W1059, W1060 und W1068 nur nach {$WARN EXPLICIT_STRING_CAST ON}, {$WARN EXPLICIT_STRING_CAST_LOSS ON} bzw. {$WARN IMMUTABLE_STRINGS ON}; {$WARN … OFF} und {$WARNINGS OFF} schalten sie ab ihrer St' +
    'elle ab, {$WARN … ERROR} meldet einen Fehler. Gemeldet wird nur, wenn beide Typen sicher bekannt sind (Variablen, Felder, Properties, Funktionsergebnisse und typisierte Konstanten der eingebauten Stri' +
    'ngtypen aus System, auch über einen einfachen Alias) und ihre Deklarationen immer mit der Anweisung übersetzt werden. Still bleiben: Verkettungen, Umwandlungen als Quelle, Umwandlungen zwischen zwei A' +
    'NSI-Typen (AnsiString, RawByteString, UTF8String; dcc wandelt nach Codepage um), eigene Stringtypen wie type AnsiString(28591), {$H-} und Delphi vor 2009. W1062 hängt von der ANSI-Codepage des überset' +
    'zenden Rechners ab (Option ansiCodePage, Vorgabe 1252; 0 schaltet diese Prüfung ab); gemeldet werden nur Zeichen, die Windows auch nicht ersatzweise abbildet: Hebräisch bis Thai, Hangul, Kana und CJK,' +
    ' Symbole und Dingbats U+2600–U+27BF und Zeichen außerhalb der BMP (Emoji). Projektoptionen der .dproj (DCC_IMPLICIT_STRING_CAST = false, true oder error usw.) gelten wie bei dcc. Korrekturen: ausdrück' +
    'lich umwandeln (string(A), AnsiString(S)); CharInSet verwenden und System.SysUtils in uses eintragen.",',
    '      "options": [',
    '        {',
    '          "name": "ansiCodePage",',
    '          "description": "ANSI-Codepage des Rechners, der übersetzt; Zeichen, die ihr sicher fehlen, meldet die Regel wie W1062, wenn sie an einen AnsiString gehen. Bekannt ist nur 1252; 0 oder ein an' +
    'derer Wert schaltet diese Prüfung ab."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "signed-unsigned-mix",',
    '      "name": "Vorzeichenbehaftet und vorzeichenlos gemischt",',
    '      "description": "Vergleich oder Rechnung (+, -, *, div, mod) mit einem vorzeichenbehafteten und einem vorzeichenlosen Operanden, deren Typen sicher bekannt sind (Variablen, Felder, Properties, Fu' +
    'nktionsergebnisse, eigene Aliase). Mit UInt64 wird der ganze Ausdruck vorzeichenlos gerechnet, ein negativer Wert wird zu einer riesigen Zahl (wie W1073, beim Vergleich wie W1023); mit Cardinal/DWORD ' +
    'und einem vorzeichenbehafteten Typ bis 32 Bit werden beide Operanden auf Int64 erweitert (wie W1023/W1024). Still bei Byte und Word, Cardinal mit Int64, Literalen, Konstanten, NativeInt/NativeUInt und' +
    ' unbekannten Typen. Mittlere Konfidenz. Korrektur: den vorzeichenlosen Operanden in Int64 umwandeln."',
    '    },',
    '{',
    '      "id": "narrowing-assignment",',
    '      "name": "Zuweisung mit möglichem Datenverlust",',
    '      "description": "Eine Zuweisung oder Inline-Variable mit einem Wert, dessen Typ breiter ist als das Ziel, ohne ausdrückliche Umwandlung: Int64 an Integer, NativeInt an Integer (Win64) und über di' +
    'e Option types z. B. Double an Single oder Extended an Double. Wie W1072 (Gleitkomma) und W1066 (Extended an Double); Ganzzahlen ohne Code, weil Delphi 13 W1071 auch mit {$WARN IMPLICIT_INTEGER_CAST_L' +
    'OSS ON} nicht meldet. Gemeldet wird nur, wenn beide Typen sicher bekannt sind (Variablen, Felder, Properties, Funktionsergebnisse, eigene Aliase und ganzzahlige Rechnungen daraus); Literale und ausdrü' +
    'ckliche Umwandlungen bleiben still. Standardmäßig aus; mittlere Konfidenz. Korrekturen: ausdrücklich umwandeln; den Typ der Deklaration des Ziels vergrößern (einzelne Variable aus derselben Datei).",',
    '      "options": [',
    '        {',
    '          "name": "types",',
    '          "description": "Gemeldete Paare Quelltyp>Zieltyp, z. B. Double>Single oder Extended>Double."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "invalid-var-argument",',
    '      "name": "Ungültiges Argument für einen var- oder out-Parameter",',
    '      "description": "Ein var- oder out-Parameter bekommt etwas, das keine Variable ist: eine Konstante, einen konstanten Ausdruck wie cMax + 1, einen const-Parameter, eine Property oder ein Funktions' +
    'ergebnis (wie E2197), eine Konstante für ein offenes Array (wie E2192) oder einen Ausdruck (wie E2036); auch @ vor einem arithmetischen oder logischen Ausdruck meldet die Regel (wie E2036). Ein String' +
    '-Element für einen Zeichen-Parameter (S[1]) ist für dcc eine Variable und bleibt still (E2354 gibt es nur unter .NET, #1383). Gemeldet nur für Routinen ohne Überladungen, deren Kopf aus der Datei oder' +
    ' dem Index bekannt ist; eingebaute Routinen wie Inc oder Move und untypisierte var-Parameter nehmen mehr an und bleiben still. Typisierte Konstanten zählen als Konstanten, außer mit {$J+}. Korrektur: ' +
    'eine lokale Variable vom Typ des Parameters übergeben, bei Properties mit write mit Rückschreiben."',
    '    },',
    '{',
    '      "id": "condition-not-boolean",',
    '      "name": "Bedingung ist kein Boolean",',
    '      "description": "Die Bedingung von if, while, until oder eines bedingten Ausdrucks hat sicher einen Typ, der kein Boolean ist: Zahl, Zeiger, Klasse, Interface, String oder Zeichen (wie E2012). An' +
    'ders als C verlangt Delphi einen Boolean. Gemeldet nur bei sicher bekanntem Typ; Boolean-Typen wie LongBool, Aufzählungen, Aliase und unbekannte Typen bleiben still. Korrektur: <> 0 (Alternative > 0),' +
    ' <> nil (Alternative Assigned), <> '''' bzw. <> #0 ergänzen."',
    '    },',
    '{',
    '      "id": "type-mismatch",',
    '      "name": "Inkompatible Typen",',
    '      "description": "Zuweisung, Argument, var-Parameter, Operator, Typumwandlung oder prozeduraler Typ mit unverträglichen Typen, beide sicher bekannt: Integer := ''abc'', ein Klassenparameter mit Stan' +
    'dardwert 0, ein statisches Array := nil, eine Prozedur ohne Ergebnis als Wert, string + Integer oder [1] + [''a''] (wie E2010); ein Operator, der für einen Operanden nicht definiert ist, etwa string - C' +
    'har, Double div 2, not ''a'' oder X is Integer (wie E2015); ein var-Argument mit anderem Typ als der Parameter, etwa Byte für Integer (wie E2033); Byte(S) eines langen Strings und die Umwandlung einer G' +
    'leitkommazahl in einen Ordinaltyp (wie E2089); Inc/Dec mit einer Gleitkommazahl oder einem String als Schrittweite und Ptr(S) (wie E2008); eine Routine mit anderer Parameterliste für einen prozedurale' +
    'n Typ bzw. eine Methode für einen Typ ohne of object und umgekehrt (wie E2009); von überladenen Routinen passt keine zum prozeduralen Typ (wie E2010); eine Routine für eine Methodenreferenz (reference' +
    ' to, auch generisch wie TFunc<string, TArray<string>>), deren Parameter in Zahl, const/var/out oder Typ abweichen, als Zuweisung oder Argument, ebenso eine anonyme Methode wie procedure(const S: strin' +
    'g) für TProc<string> (wie E2010); eine parameterlose Funktion, deren Ergebnis genau den prozeduralen Typ des Ziels hat, ohne () zugewiesen oder übergeben (wie E2010: Delphi nimmt die Funktion selbst).' +
    ' Wie bei dcc hat Result den Typ aus dem interface-Teil, und von zwei Deklarationen desselben lokalen Namens gilt die letzte. Gemeldet nur, wenn beide Seiten sicher bekannt sind und ihre Deklarationen ' +
    'immer mit der Stelle übersetzt werden; Records (class operator Implicit), Variant, Zeiger, Teilbereiche, Generics, überladene Routinen und with-Blöcke bleiben still. Korrektur nur für die Funktion ohn' +
    'e (): () ergänzen. Sonst keine Korrektur: Welche Seite falsch ist, weiß nur der Entwickler."',
    '    },',
    '{',
    '      "id": "for-in-not-enumerable",',
    '      "name": "for-in über einen Typ ohne Enumerator",',
    '      "description": "Eine for-in-Schleife läuft über einen Typ, der sich nicht aufzählen lässt: Zahl, Zeiger, Zeichen oder Boolean, oder eine Klasse, ein Record bzw. Interface ohne öffentliches GetEn' +
    'umerator, auch nicht geerbt oder aus einem Helper (wie E2430); oder der Enumerator aus GetEnumerator hat kein öffentliches MoveNext bzw. Current (wie E2431). Strings, Arrays und Mengen gehen. Gemeldet' +
    ' nur, wenn der Typ und alle Vorfahren bekannt sind; generische und unbekannte Typen bleiben still. Keine Korrektur; hat der Typ Count, nennt die Meldung eine Schleife mit Index."',
    '    },',
    '{',
    '      "id": "type-kind-required",',
    '      "name": "Ausdruck oder Deklaration hat nicht die geforderte Typart",',
    '      "description": "Eine Operation verlangt eine Typart, die der Operand sicher nicht hat: ein Index auf einer Zahl, einem Boolean, Zeichen oder Aufzählungswert (wie E2016); ^ auf einem solchen Wert' +
    ', einer Klasse, einem Record oder Interface (wie E2017); Punkt oder with auf einem solchen Wert (wie E2018); ein object-Typ mit einem Vorfahr, der kein object-Typ ist, TypeOf auf einem einfachen Wert ' +
    'und Dispose mit Destruktor auf einem Zeiger auf einen einfachen Typ (wie E2019); eine Klasse mit einem Record, einer Klassenreferenz, Aufzählung oder einem einfachen Typ als Vorfahr (wie E2021); ein C' +
    'lass-Helper, dessen Vorfahr kein Helper ist (wie E2022); New mit Konstruktor auf einem Zeiger auf einen einfachen Typ (wie E2467); ein Record-Helper für eine Klasse oder ein Interface (wie E2474); ein' +
    'e Methode ohne class über den Klassentyp aufgerufen, außerhalb von Methoden der Klasse und ihrer Nachfahren (wie E2076); Slice außerhalb eines Arguments für ein offenes Array (wie E2193); ein Record i' +
    'n einem Array an array of const (wie E2150); Write/Writeln bzw. Read/Readln mit einer Klasse, einem Record oder Interface (wie E2054, E2055). Gemeldet nur bei sicher bekanntem Typ: unbekannte Typen, b' +
    'edingte Deklarationen, sichtbare Helper, Units außerhalb des Index, Records mit Implicit-Operator und unbekannte Vorfahren bleiben still. Korrekturen: ^ vor einem Punkt bei Klassen, Records und Interf' +
    'aces entfernen; in Write/Writeln Objekt.ToString schreiben."',
    '    },',
    '{',
    '      "id": "generic-inference-failed",',
    '      "name": "Typargumente lassen sich nicht ableiten",',
    '      "description": "Ein Aufruf einer generischen Methode ohne Typargumente, deren Typparameter sich aus den Argumenten nicht ableiten lassen: ein Typparameter, der in keinem Parameter vorkommt, etwa' +
    ' nur im Ergebnis (wie E2531), oder Argumente verschiedener Art (Zahl, Zeichenkette, Boolean) für Parameter, deren Typ derselbe Typparameter ist (wie E2532). E2531 meldet die Regel als Anweisung, als A' +
    'ufruf mit Klammern und auf der rechten Seite einer Zuweisung an einen Wert bekannten, nicht prozeduralen Typs, und nur, wenn jede Überladung einen solchen Typparameter hat. E2532 meldet sie nur bei ge' +
    'nau einer Routine ohne overload; Argumente unbekannten Typs (Variant, Klassen, Ausdrücke) und Zahlen verschiedener Breite halten sie still. Wie argument-count-mismatch schweigt sie bei Deklarationen i' +
    'n bedingten Zweigen und bei Namen, die ein unbekannter Vorfahr verdecken kann."',
    '    },',
    '{',
    '      "id": "dunitx-areequal-length",',
    '      "name": "Assert.AreEqual mit Ganzzahl und NativeInt",',
    '      "description": "Assert.AreEqual bzw. Assert.AreNotEqual mit einer Ganzzahl auf der einen und einem NativeInt auf der anderen Seite: Length, High oder Low eines dynamischen Arrays (ab Delphi 12 N' +
    'ativeInt) oder ein Ausdruck, dessen Typ sicher NativeInt bzw. NativeUInt ist (TList<T>.Count mit der RTL im Index). Keine der Überladungen Integer, Int64, Double … passt eindeutig, Delphi fällt auf Ar' +
    'eEqual<T> zurück und kann T nicht ableiten (wie E2532). Free Pascal übersetzt den Aufruf, deshalb fällt der Fehler erst beim Bau mit Delphi auf. Strings (Length liefert Integer), statische Arrays, Aus' +
    'drücke unbekannten Typs, Aufrufe mit Typargument und eine bekannte Delphi-Version vor 12 bleiben still. Korrektur (sicher, auch für die ganze Datei): Integer(...) um die NativeInt-Seite."',
    '    },',
    '{',
    '      "id": "caption-string-helper",',
    '      "name": "String-Helfer auf TCaption",',
    '      "description": "Eine Methode von TStringHelper (StartsWith, Contains, Trim, ToUpper, Length …) wird auf einem Ausdruck vom Typ TCaption aufgerufen, etwa Caption oder Text eines Steuerelements. T' +
    'Caption ist als type string deklariert, ein eigener Typ, für den der String-Helfer nicht gilt (wie E2018). Free Pascal nimmt den Aufruf an. Gemeldet nur, wenn der Typ des Ausdrucks sicher TCaption ist' +
    '. Korrektur (sicher): string(...) um den Ausdruck."',
    '    },',
    '{',
    '      "id": "argument-count-mismatch",',
    '      "name": "Falsche Anzahl Argumente",',
    '      "description": "Ein Aufruf übergibt mehr Argumente, als die Routine Parameter hat (wie E2034), oder weniger als Parameter ohne Standardwert (wie E2035), auch als Anweisung ohne Klammern. Geprüft' +
    ' wird nur, wenn der Name sicher genau eine Routine meint: Überladungen, varargs, Typumwandlungen, Variablen prozeduralen Typs, Bezeichner von System ohne Quelltext und Deklarationen in bedingten Zweig' +
    'en bleiben beim Compiler (E2250). Eine Funktion mit zu vielen Argumenten meldet die Regel nur bei bekanntem, nicht prozeduralem Ergebnistyp. Korrektur: Signaturhilfe öffnen setzt die Schreibmarke in d' +
    'ie Klammern und öffnet den Parameter-Hint (ergänzt () bei Bedarf)."',
    '    },',
    '{',
    '      "id": "overload-resolution",',
    '      "name": "Überladung nicht auflösbar oder mehrdeutig",',
    '      "description": "Ein Aufruf einer überladenen Routine oder Methode passt zu keiner Überladung (wie E2250), etwa ein Gleitkommawert, wo nur Integer und string angeboten sind, oder ist mehrdeutig (' +
    'wie E2251), weil sich die passenden Überladungen nur in Parametern mit Standardwert unterscheiden. Geprüft wird nur, wenn die Liste der Überladungen sicher vollständig ist: System und alle Units in us' +
    'es im Index, keine gleichnamige freie Routine in einer anderen Unit, bekannte Vorfahren, keine bedingten, generischen, verschachtelten oder varargs-Deklarationen, kein with. Als unpassend gelten nur e' +
    'ingebaute Typfamilien ohne implizite Umwandlung (Gleitkomma an Ganzzahl, string an Char, Boolean an Zahl …), Aliase wie ihr Grundtyp; Records mit Implicit-Operator, Klassen, Zeiger, offene Arrays, Var' +
    'iant und überladene Aufrufe im Argument bleiben beim Compiler. Mehrdeutig heißt: Alle passenden Überladungen derselben Klasse bzw. Unit haben für die übergebenen Argumente genau deren Typen. Korrektur' +
    ': Signaturhilfe öffnen zeigt alle Überladungen."',
    '    }');

implementation

end.
