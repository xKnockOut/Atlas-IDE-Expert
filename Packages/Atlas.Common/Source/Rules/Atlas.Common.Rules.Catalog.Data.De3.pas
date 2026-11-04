unit Atlas.Common.Rules.Catalog.Data.De3;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  CatalogLinesDe3: array[0..60] of string = (
    '      "name": "Typargument verletzt eine Einschränkung",',
    '      "description": "Ein Typargument erfüllt die Einschränkung seines Typparameters nicht: class (wie E2511), record (wie E2512), constructor (wie E2513), ein Interface (wie E2514) oder eine Basiskla' +
    'sse (wie E2515). In Methoden eines generischen Typs dieser Datei meldet die Regel außerdem T.Create ohne constructor-Einschränkung (wie E2568) und Methodenaufrufe auf Werten eines Typparameters ganz o' +
    'hne Einschränkung (wie E2571). Den generischen Typ löst die Namensauflösung samt Zahl der Typparameter auf, seine Einschränkungen stammen aus seiner Deklaration in der Datei oder im Symbolindex. Argum' +
    'ente, die selbst Typparameter sind, Aliase und Typen mit unvollständiger Vorfahrenkette meldet die Regel nicht. Korrektur für einen Typparameter dieser Datei, der allein in seiner Gruppe steht: die Ei' +
    'nschränkung ergänzen (T: class, constructor bzw. T: class)."',
    '    },',
    '    {',
    '      "id": "generic-inference-failed",',
    '      "name": "Typargumente lassen sich nicht ableiten",',
    '      "description": "Ein Aufruf einer generischen Methode ohne Typargumente, deren Typparameter sich aus den Argumenten nicht ableiten lassen: ein Typparameter, der in keinem Parameter vorkommt, etwa' +
    ' nur im Ergebnis (wie E2531), oder Argumente verschiedener Art (Zahl, Zeichenkette, Boolean) für Parameter, deren Typ derselbe Typparameter ist (wie E2532). E2531 meldet die Regel als Anweisung, als A' +
    'ufruf mit Klammern und auf der rechten Seite einer Zuweisung an einen Wert bekannten, nicht prozeduralen Typs, und nur, wenn jede Überladung einen solchen Typparameter hat. E2532 meldet sie nur bei ge' +
    'nau einer Routine ohne overload; Argumente unbekannten Typs (Variant, Klassen, Ausdrücke) und Zahlen verschiedener Breite halten sie still. Wie argument-count-mismatch schweigt sie bei Deklarationen i' +
    'n bedingten Zweigen und bei Namen, die ein unbekannter Vorfahr verdecken kann."',
    '    },',
    '    {',
    '      "id": "unresolved-type",',
    '      "name": "Typ in einer Deklaration nicht gefunden",',
    '      "description": "Ein Typname in einer Deklaration (Feld, Parameter, Ergebnis, Vorfahr, Interface-Liste, Variable, Typargument) ist nicht deklariert (wie E2003, beim Ziel eines Zeigertyps wie E256' +
    '4) oder kein Typ: eine Variable oder ein Mitglied hinter einem Punkt wie E2005, eine Routine wie E2007, eine Konstante wie E2029 (Delphi liest sie als Anfang eines Teilbereichs und erwartet ''..''). Typ' +
    'en, die der Compiler ohne Deklaration in System.pas kennt (Text, TextFile, Real48, OpenString …), gelten als deklariert. Ergänzt unresolved-identifier, das nur Anweisungen prüft. Dieselben Vorbedingun' +
    'gen wie bei unresolved-attribute: System im Symbolindex, alle Units aus uses bekannt, nicht in {$IF…}-Blöcken. Typparameter, Namen, die die Datei irgendwo als Typ deklariert (auch verschachtelt), und ' +
    'Namen, die der Index als verschachtelten Typ kennt (geerbte innere Typen), meldet die Regel nicht. Korrektur: die Unit, die den Typ (mit gleich vielen Typparametern) deklariert, in uses aufnehmen."',
    '    },',
    '    {',
    '      "id": "class-reference-nonvirtual-constructor",',
    '      "name": "Konstruktor über Klassenreferenz nicht virtuell",',
    '      "description": "Create über eine Klassenreferenz (class of TBasis), deren Konstruktor nicht virtual ist. Unter Win32 und Win64 übersetzt das ohne Meldung, erzeugt aber immer über den Konstruktor' +
    ' von TBasis: Felder, die Nachfahren in ihren eigenen Konstruktoren setzen, bleiben leer (wie E2391). Der Empfänger kann eine Variable, ein Feld, ein Parameter oder ein Funktionsergebnis vom Typ einer ' +
    'Klassenreferenz sein; den Konstruktor löst die Namensauflösung in der nächsten Klasse auf, die ihn deklariert, Überladungen nach Zahl der Argumente. Still, wenn eine passende Überladung virtual, dynam' +
    'ic, override oder abstract ist, wenn eine Deklaration in einem anderen Zweig der bedingten Übersetzung steht und wenn ein Typ nicht auflösbar ist. Korrektur, wenn der Konstruktor in dieser Datei steht' +
    ': virtual an ihn und override an die gleichlautenden Konstruktoren der Nachfahren in dieser Datei."',
    '    },',
    '    {',
    '      "id": "jump-outside-allowed-scope",',
    '      "name": "Break, Continue oder Exit an unzulässiger Stelle",',
    '      "description": "Break oder Continue außerhalb einer Schleife (wie E2097) bzw. Break, Continue oder Exit, die einen finally-Block verlassen (wie E2126). Delphi meldet beides erst beim Übersetzen;' +
    ' häufig nach dem Herausziehen eines Schleifenrumpfs in eine eigene Methode. Eine Schleife ganz im finally-Block darf Break und Continue verwenden. Routinen und anonyme Methoden beginnen neu: Ein Break' +
    ' in einer anonymen Methode gehört nicht zur Schleife um sie herum. Gemeldet werden nur einfache Aufrufe (nicht TMonitor.Exit(FLock)) und nicht, wenn die Datei eine Routine oder Variable dieses Namens ' +
    'deklariert. Korrektur außerhalb eines finally-Blocks: Break durch Exit ersetzen."',
    '    },',
    '    {',
    '      "id": "reraise-outside-handler",',
    '      "name": "raise ohne Argument außerhalb eines Handlers",',
    '      "description": "raise; ohne Exception-Objekt ist nur in einem except-Block erlaubt (wie E2145); Delphi meldet es erst beim Übersetzen. Es passiert in einer lokalen Prozedur, die aus dem Handler ' +
    'gerufen wird, in einem finally-Block oder nach dem Verschieben von Code. Routinen und anonyme Methoden beginnen neu. Still bleibt die Regel in anonymen Methoden innerhalb eines except-Blocks und in Ro' +
    'utinen, in denen der Parser einen Fehler meldet. Keine Korrektur: eine neue Exception auslösen (raise EImport.Create(…)) oder den Code in den Handler verschieben. raise E; im Handler meldet reraise-ex' +
    'ception-object."',
    '    },',
    '    {',
    '      "id": "label-misuse",',
    '      "name": "Sprungmarke falsch verwendet",',
    '      "description": "Eine Marke ist doppelt gesetzt (wie E2073), deklariert und angesprungen, aber nie gesetzt (E2074), gesetzt oder angesprungen, ohne in der aktuellen Routine deklariert zu sein (E2' +
    '093; ein goto auf eine nirgends deklarierte und nie gesetzte Marke meldet die Regel syntax als E2031), oder goto springt in einen try-Block hinein oder aus ihm heraus, auch zwischen try-Teil und excep' +
    't bzw. finally (E2127). Delphi meldet das erst beim Übersetzen. Marken gehören zu einer Routine bzw. zum Programmblock; eine lokale Prozedur kann keine Marke der umgebenden Routine anspringen. Doppelt' +
    'e Marken in bedingten Zweigen, die sich ausschließen, bleiben still, ebenso Routinen mit asm-Block, weil Marken im asm nicht im Syntaxbaum stehen. Keine Korrektur."',
    '    },',
    '    {',
    '      "id": "for-variable-misuse",',
    '      "name": "Schleifenvariable verändert oder nicht lokal",',
    '      "description": "Der Variablen einer for-Schleife wird im Rumpf zugewiesen oder sie wird mit Inc/Dec verändert (wie E2081), sie wird als var- bzw. out-Parameter an eine Routine dieser Datei überg' +
    'eben (wie W1015) oder sie ist keine einfache lokale Variable: Feld der eigenen Klasse oder lokale Variable der umgebenden Routine (wie E1019) bzw. globale Variable der Unit (wie W1019, Delphi warnt nu' +
    'r). Delphi meldet das erst beim Übersetzen. Parameter, unbekannte Namen und Schleifen in with-Anweisungen bleiben still, ebenso anonyme Methoden im Rumpf und Routinen mit Parserfehlern. Korrekturen: a' +
    'uf eine while-Schleife umstellen (nicht bei Continue im Rumpf) bzw. for var verwenden, wenn die Routine den Namen sonst nicht benutzt."',
    '    },',
    '    {',
    '      "id": "for-variable-after-loop",',
    '      "name": "Schleifenvariable nach der Schleife gelesen",',
    '      "description": "Nach einer for-Schleife, die normal endet (ohne Break), ist die Schleifenvariable undefiniert. Die Regel meldet das erste Lesen der Variable auf einem Weg vom normalen Schleifene' +
    'nde, bevor ihr erneut zugewiesen wird (wie W1037). Geprüft werden nur einfache lokale Variablen der Routine; for var, Felder, globale Variablen, Lesen nur im Rumpf, Argumente von Routinen, die out-Par' +
    'ameter sein könnten, und Routinen mit unvollständigem Ablaufgraphen bleiben still. Korrektur: auf eine while-Schleife umstellen, deren Zähler danach einen festen Wert hat."',
    '    },',
    '    {',
    '      "id": "argument-count-mismatch",',
    '      "name": "Falsche Anzahl Argumente",',
    '      "description": "Ein Aufruf übergibt mehr Argumente, als die Routine Parameter hat (wie E2034), oder weniger als Parameter ohne Standardwert (wie E2035), auch als Anweisung ohne Klammern. Geprüft' +
    ' wird nur, wenn der Name sicher genau eine Routine meint: Überladungen, varargs, Typumwandlungen, Variablen prozeduralen Typs, Bezeichner von System ohne Quelltext und Deklarationen in bedingten Zweig' +
    'en bleiben beim Compiler (E2250). Eine Funktion mit zu vielen Argumenten meldet die Regel nur bei bekanntem, nicht prozeduralem Ergebnistyp. Korrektur: Signaturhilfe öffnen setzt die Schreibmarke in d' +
    'ie Klammern und öffnet den Parameter-Hint (ergänzt () bei Bedarf)."',
    '    },',
    '    {',
    '      "id": "overload-resolution",',
    '      "name": "Überladung nicht auflösbar oder mehrdeutig",',
    '      "description": "Ein Aufruf einer überladenen Routine oder Methode passt zu keiner Überladung (wie E2250), etwa ein Gleitkommawert, wo nur Integer und string angeboten sind, oder ist mehrdeutig (' +
    'wie E2251), weil sich die passenden Überladungen nur in Parametern mit Standardwert unterscheiden. Geprüft wird nur, wenn die Liste der Überladungen sicher vollständig ist: System und alle Units in us' +
    'es im Index, keine gleichnamige freie Routine in einer anderen Unit, bekannte Vorfahren, keine bedingten, generischen, verschachtelten oder varargs-Deklarationen, kein with. Als unpassend gelten nur e' +
    'ingebaute Typfamilien ohne implizite Umwandlung (Gleitkomma an Ganzzahl, string an Char, Boolean an Zahl …), Aliase wie ihr Grundtyp; Records mit Implicit-Operator, Klassen, Zeiger, offene Arrays, Var' +
    'iant und überladene Aufrufe im Argument bleiben beim Compiler. Mehrdeutig heißt: Alle passenden Überladungen derselben Klasse bzw. Unit haben für die übergebenen Argumente genau deren Typen. Korrektur' +
    ': Signaturhilfe öffnen zeigt alle Überladungen."',
    '    },',
    '    {',
    '      "id": "method-without-self",',
    '      "name": "Methode braucht Self nicht",',
    '      "description": "Eine Methode einer Klasse oder eines Records nutzt weder Self noch Instanzmitglieder (Felder, Properties, Instanzmethoden, inherited). Sie ist nicht virtuell, kein Ereignis der F' +
    'ormulardatei, implementiert kein Interface und wird nicht als Methodenzeiger verwendet. Experimentell: nur aktiv, wenn in atlas.json eingeschaltet; schweigt mit refactoring.methodKind aus. Schnellkorr' +
    'ektur: in eine class-Methode umwandeln (class … static mit refactoring.methodKindStatic); die Code-Aktionen bieten außerdem Aufrufe über die Klasse, eine freie Routine und einen Record-Helper für den ' +
    'Typ des ersten Parameters, jeweils mit Vorschau aller geänderten Aufrufe."',
    '    }',
    '  ]',
    '}',
    '');

implementation

end.
