unit Atlas.Common.Rules.Catalog.Data.De.CompilerSyntax;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeCompilerSyntax: array[0..188] of string = (
    '{',
    '      "id": "syntax",',
    '      "name": "Syntaxfehler",',
    '      "description": "Der Quelltext lässt sich nicht lesen. Die Meldung nennt wie der Compiler, was erwartet und was gefunden wurde („'';'' erwartet, aber ''end'' gefunden (wie E2029).“), und trägt den Co' +
    'mpilercode: fehlendes '';'' (E2066 zwischen Anweisungen, E2029 in Deklarationen), '';'' vor else (E2153), offener String (E2052) oder Kommentar mit Startzeile (E2057), Anweisungen im interface-Teil (E2050' +
    '), Bezeichner nach einem Punkt am Ende (E2372), strict ohne private oder protected (E2375), class vor etwas anderem als einer Routine, var oder property (E2123), eine Zahl mit leerem Exponenten wie 1.' +
    '5e (E2053), absolute mit einer Adresse statt einer Variablen (E2088), try ohne except oder finally (E2125), for ohne Variable (E2088). Prüfungen am fertigen Baum: procedure mit Ergebnistyp (E2025), De' +
    'klaration einer function ohne Ergebnistyp (E2023; die Kurzform der Implementierung ist erlaubt), Wertparameter ohne Typ (E2067), lokale Variable mit Anfangswert (E2195) oder mehrere Variablen mit eine' +
    'm Anfangswert (E2196), Klassen-, Interface- oder Objekttyp im var-Abschnitt (E2058, in einer Routine dazu E2059) oder lokal in einer Routine (E2059), class operator in einer Klasse, einem Interface od' +
    'er object-Typ (E2123; Operatoren gibt es nur in Records). Die Codes folgen Delphi 13; ältere Versionen meldeten stattdessen E2357, E2060 und E2061, label im interface-Teil (E2049) und goto auf eine ni' +
    'cht deklarierte Marke (E2031; eine Marke der umgebenden Routine meldet label-misuse als E2093). Nach einem offenen String oder Kommentar fallen die Folgefehler weg, weil der Compiler dort abbricht. In' +
    'aktive {$IFDEF}-Zweige werden nicht gemeldet. Korrekturen: '';'' vor else entfernen (sicher, auch beim Speichern), '';'' ergänzen, String schließen, Kommentar am Ende seiner ersten Zeile schließen."',
    '    },',
    '{',
    '      "id": "language-feature",',
    '      "name": "Sprachmerkmal einer neueren Delphi-Version",',
    '      "description": "Der Code nutzt ein Sprachmerkmal, das der Sprachstand des Projekts noch nicht kennt: Inline-Variable und -Konstante (Delphi 10.3), Managed Record mit class operator Initialize/Fi' +
    'nalize (Delphi 10.4), Ziffern-Trennzeichen 1_000 und Binärliteral %1010 (Delphi 11), mehrzeiliger String '''''' (Delphi 12), If-Ausdruck, „is not“ und „not in“ (Delphi 13). Der Sprachstand ist die ältere' +
    ' aus delphiVersion und minDelphiVersion in atlas.json: minDelphiVersion nennt die älteste Delphi-Version, mit der das Projekt noch übersetzen muss (z. B. „12“ für Code, den Delphi 12 und 13 übersetzen' +
    '). Ohne beide Angaben meldet Atlas nichts. Inaktive Zweige {$IF CompilerVersion >= …} bleiben still, so kann Code für mehrere Versionen nebeneinander stehen. Gemeldet im Editor, von --check, check_cod' +
    'e und dem Claude-Code-Hook (hook_check). Code-Aktionen und Schnellbefehle erzeugen keine Merkmale über den Sprachstand hinaus."',
    '    },',
    '{',
    '      "id": "asm-invalid",',
    '      "name": "Ungültige Anweisung im Inline-Assembler",',
    '      "description": "Anweisungen in asm-Blöcken, die dcc ablehnt: fehlender Operand (mov eax, ) und esp als Indexregister mit Faktor ([eax + esp * 2]) wie E2105, zwei Register verschiedener Größe (mo' +
    'v al, ebx), lea mit einer Zahl und eine Zahl als Ziel von mov wie E2107 (dcc meldet hier E2107 statt E2108 und E2116), db mit einer lokalen Variablen der Routine wie E2109, OFFSET a + OFFSET b wie E21' +
    '11, eine Zahl über 64 Bit wie E2113, eine Stringkonstante mit mehr als 4 Zeichen an einem 32-Bit-Register wie E2114 und Division durch null (/ 0, mod 0) wie E2118. Gemeldet werden nur mit dcc bestätig' +
    'te Formen, höchstens ein Befund je Anweisung. Anweisungen mit einer Compiler-Direktive oder einem { }-Kommentar in derselben Zeile (Free Pascal schreibt so ARM-Registerlisten), die übrigen Datenbefehl' +
    'e, Register von Win64 (rax, r8 …, unter Win32 mögliche Variablennamen) und Dateien für Free Pascal ({$MODE …}, {$ASMMODE …}) bleiben still."',
    '    },',
    '{',
    '      "id": "for-high-to-low",',
    '      "name": "for-Schleife zählt mit to abwärts",',
    '      "description": "Die Schleife beginnt beim oberen Wert (High, Count - 1) und endet beim unteren, verwendet aber to. Sie läuft nie; gemeint war downto. Ebenso Schleifen mit konstanten Grenzen, die' +
    ' nie laufen, etwa for I := 10 to 1, auch mit Vorzeichen, Hex- oder Zeichenliteralen (wie H2135). Gleiche Grenzen, Ausdrücke, benannte Konstanten und aufsteigende Grenzen bleiben still. Korrektur: to d' +
    'urch downto ersetzen."',
    '    },',
    '{',
    '      "id": "conditional-expression-version",',
    '      "name": "Bedingungsausdruck vor Delphi 13",',
    '      "description": "Den Bedingungsausdruck X := if C then A else B gibt es erst ab Delphi 13; ein Projekt, das noch mit Delphi 12 oder älter übersetzen muss, scheitert hier (wie E2029). Gemeldet wir' +
    'd der äußerste Ausdruck, nicht in Zweigen von {$IF}, die nach CompilerVersion, RTLVersion, VERnnn oder Declared fragen. Ohne bekannte Delphi-Version still. Korrektur (auch für die ganze Unit): in eine' +
    ' if-Anweisung umwandeln, die Anweisung je Zweig wiederholt; nicht angeboten, wenn der Rest der Anweisung Seiteneffekte hat."',
    '    },',
    '{',
    '      "id": "comparison-as-statement",',
    '      "name": "Vergleich statt Zuweisung als Anweisung",',
    '      "description": "Ein Vergleich wie Result = 0; oder FAktiv = True; steht als eigene Anweisung; gemeint war :=. Delphi meldet E2014 erst beim Übersetzen. Bei = mit zuweisbarer linker Seite (Variab' +
    'le, Feld, Element, Ziel eines Zeigers) ersetzt die Korrektur = durch :=. Andere Vergleiche und Ausdrücke, deren Wert verfällt (A <> B;, A + B;, not A;, ein Literal), meldet die Regel ohne Korrektur, e' +
    'benso einen Aufruf links."',
    '    },',
    '{',
    '      "id": "field-after-method",',
    '      "name": "Feld nach Methoden im selben Abschnitt",',
    '      "description": "In einem Sichtbarkeitsabschnitt einer Klasse, eines Objekts oder Records folgt eine Felddeklaration auf eine Methode oder Property. Delphi verlangt Felder zuerst oder einen neuen' +
    ' Abschnitt bzw. var (E2169); FPC übersetzt das. Korrekturen: das Feld samt Attributen und Kommentaren an den Anfang des Abschnitts verschieben oder var davor setzen. In Records steht var vorn, weil da' +
    's Verschieben das Speicherlayout ändert. Gemeldet wird ein Feld nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird; mit bedingten Zweigen dazwischen gibt es nur var."',
    '    },',
    '{',
    '      "id": "overload-directive-missing",',
    '      "name": "Überladung ohne overload oder mit gleicher Signatur",',
    '      "description": "Zwei Routinen oder Methoden gleichen Namens im selben Gültigkeitsbereich (ein Typ, die Unit über interface und implementation, die in einer Routine verschachtelten Routinen), von' +
    ' denen mindestens eine kein overload trägt (wie E2254, bzw. E2267, wenn es der früheren fehlt), oder zwei Überladungen mit gleichen Parameterarten und -typen (wie E2252, bzw. E2301 mit auch gleichem E' +
    'rgebnistyp). Ein Rumpf zu einer früheren Deklaration (interface, forward) zählt nicht. Operatoren, Methodenrümpfe und Deklarationen in verschiedenen Zweigen desselben {$IF} bleiben außen vor. Korrektu' +
    'r: overload; an alle Deklarationen ohne anhängen, vor den übrigen Direktiven."',
    '    },',
    '{',
    '      "id": "duplicate-declaration",',
    '      "name": "Bezeichner doppelt deklariert",',
    '      "description": "Ein Bezeichner ist im selben Gültigkeitsbereich zweimal deklariert (wie E2004): lokale Variable, Konstante, Typ oder Label und ein Parameter der Routine, zwei Felder, ein Feld un' +
    'd eine Methode oder Property eines Typs, zwei Typen, Konstante und Variable der Unit über interface und implementation hinweg. Ebenso eine Unit doppelt in uses oder in den uses-Klauseln von interface ' +
    'und implementation zugleich (Option checkUses). Überladungen und Rümpfe von Routinen, eine Vorwärtsdeklaration und ihr Typ, TList neben TList<T> und Deklarationen in verschiedenen Zweigen desselben {$' +
    'IF} zählen nicht. Korrektur: zweite Deklaration entfernen (den ganzen var-, const-, type- oder label-Abschnitt, wenn sie seine einzige war; bei uses den doppelten Eintrag); keine bei Parametern, Metho' +
    'den und Properties. Unter demselben Namen überladene default-Array-Properties prüft default-property-invalid (#1380).",',
    '      "options": [',
    '        {',
    '          "name": "checkUses",',
    '          "description": "Doppelte Einträge in uses-Klauseln melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "conditional-directive-unbalanced",',
    '      "name": "Bedingte Direktiven unvollständig oder unbekannt",',
    '      "description": "Ein {$IFDEF}, {$IFNDEF}, {$IFOPT} oder {$IF}, das nie geschlossen wird, sodass der Rest der Datei an seiner Bedingung hängt (wie E2095, bei {$IF} E2280); {$ELSE}, {$ELSEIF}, {$EN' +
    'DIF} oder {$IFEND} ohne passendes {$IF…} oder nach {$ELSE} (wie E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} oder {$UNDEF} ohne gültiges Symbol (wie E2173); eine unbekannte Direktive oder ein unbekannter {$' +
    'WARN}-Bezeichner (wie E1030, vor Delphi 13 W1030; der Code folgt delphiVersion), mit dem nächstliegenden bekannten Namen als Korrektur; {$POPOPT} ohne {$PUSHOPT} (wie W1078) oder {$PUSHOPT} ohne {$POP' +
    'OPT} (wie W1079); ein ungültiger Wert für {$ALIGN} bzw. {$A} (wie E2573). Unbekannte Namen prüft die Regel nicht in Zweigen, deren Bedingung FPC abfragt, {$PUSHOPT}/{$POPOPT} nur, wenn keines davon in' +
    ' einem bedingten Zweig steht. Korrekturen: {$ENDIF} vor der ersten Leerzeile hinter dem offenen Block ergänzen, überzählige Direktive entfernen, Tippfehler korrigieren."',
    '    },',
    '{',
    '      "id": "compiler-directive-invalid",',
    '      "name": "Compileranweisung ungültig oder Datei aus {$I}/{$R} fehlt",',
    '      "description": "Eine Compileranweisung außerhalb bedingter Zweige, die dcc ablehnt oder selbst meldet: {$MESSAGE WARN ''Text''} und {$MESSAGE HINT ''Text''} zeigen ihren Text als Warnung bzw. Hinwei' +
    's (wie W1054, H1054); {$WEAKPACKAGEUNIT ON} zusammen mit {$DENYPACKAGEUNIT ON} (wie E2222); {$DESIGNONLY} oder {$RUNONLY} in einer Unit statt in einem Package (wie E2224); {$OBJTYPENAME} für einen sch' +
    'lichten Alias wie TZahl = Integer (wie E2560); {$CODEPAGE} mit einer Zahl über 65535 (wie E1030); eine Datei aus {$I} bzw. {$INCLUDE}, die es weder neben der Unit noch in den Suchpfaden des Projekts g' +
    'ibt (wie F1026); eine Include-Datei, die sich über unbedingte {$I} selbst einbindet, direkt oder über weitere Include-Dateien (wie E2245); eine Ressourcendatei aus {$R} bzw. {$RESOURCE}, die sich nich' +
    't finden lässt (wie E1026). Dateien sucht die Regel wie dcc: neben der Unit, im Projektordner, in den Suchpfaden, DCC_IncludePath, DCC_ResourcePath und den Bibliothekspfaden der Installation; ohne Pro' +
    'jekt, mit unbekannter Installation oder offenem Makro in einem Pfad bleibt sie still. Nicht geprüft: {$R Name.res Name.rc} und eine .res neben einer gleichnamigen .rc (die IDE übersetzt sie vor dem Co' +
    'mpiler), Formulare ({$R *.dfm}, form-resource-missing), Masken wie {$R *.res}, Schalter wie {$I+} und {$R-} sowie {$MESSAGE} ohne Art oder mit ERROR bzw. FATAL. Direktiven in bedingten Zweigen übergeh' +
    't die Regel, denn dcc meldet nur, was es übersetzt."',
    '    },',
    '{',
    '      "id": "unit-name-mismatch",',
    '      "name": "Unit-Name passt nicht zum Dateinamen",',
    '      "description": "Der Name hinter unit weicht vom Dateinamen ab, meist nach dem Umbenennen der Datei außerhalb der IDE (wie E1038, W1038). Groß-/Kleinschreibung zählt nicht, Punkte im Namen schon.' +
    ' In Programmen, Bibliotheken und Packages wird außerdem ein Eintrag uses X in ''Datei.pas'' gemeldet, dessen Datei eine andere Unit deklariert (wie E2085); die Regel liest dazu die Datei. Passt dort auc' +
    'h der Name der Unit nicht zu ihrer Datei, meldet Delphi 13 nur E1038 in der Unit, und der uses-Eintrag bleibt still. Programme, Bibliotheken und Packages selbst vergleicht sie nicht mit dem Dateinamen' +
    ', weil der Compiler das auch nicht tut. {$WARN UNIT_NAME_MISMATCH OFF} oder {$WARNINGS OFF} vor dem Unit-Namen schaltet die Regel wie den Compiler ab. Korrekturen: Unit-Namen an den Dateinamen anpasse' +
    'n (die Datei umbenennen bleibt Sache der IDE) bzw. den uses-Eintrag auf die Unit der Datei ändern."',
    '    },',
    '{',
    '      "id": "text-after-final-end",',
    '      "name": "Text nach dem abschließenden end.",',
    '      "description": "Nach dem abschließenden end. einer Unit, eines Programms, einer Bibliothek oder eines Packages steht noch Quelltext. Der Compiler ignoriert ihn (wie W1011); meist ist es Code, de' +
    'r beim Einfügen ans Dateiende geraten ist und nie übersetzt wird. Kommentare und Direktiven werden nicht gemeldet (Option allowComments). Die Regel sucht das abschließende end. hinter dem letzten Absc' +
    'hnitt des Syntaxbaums und schweigt, solange der Parser Fehler meldet oder end. in einem {$IF…}-Zweig steht; {$WARNINGS OFF} vor end. schaltet sie ab. Schnellkorrektur: Text nach end. entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "allowComments",',
    '          "description": "Kommentare und Direktiven nach end. erlauben."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "exports-invalid",',
    '      "name": "exports-Klausel unzulässig",',
    '      "description": "Eine exports-Klausel in einer Routine (wie E2191), der Export einer threadvar, einer mit local deklarierten Routine, einer Konstanten oder eines Typs (wie E2276) oder derselbe Ex' +
    'portname zweimal über name ''…'' (wie E2287). Variablen und denselben Eintrag zweimal ohne name übersetzt Delphi 13; die meldet die Regel nicht. Namen löst die Regel nur gegen globale Deklarationen der ' +
    'Datei auf; Namen aus anderen Units und Namen mit Punkt bleiben still, ebenso zwei Einträge in sich ausschließenden {$IF…}-Zweigen. Überladene Routinen mit verschiedenen Parameterlisten oder Exportname' +
    'n gelten als verschiedene Einträge. Ergänzt dll-export-unsafe (#973). Schnellkorrektur: doppelten Eintrag entfernen."',
    '    },',
    '{',
    '      "id": "file-encoding-unsupported",',
    '      "name": "Kodierung oder Zeichen, die der Compiler nicht liest",',
    '      "description": "Die Datei ist UTF-32 kodiert (wie F2438; erkannt an der BOM, dann keine weiteren Meldungen), oder der Code außerhalb von Strings, Kommentaren und Direktiven enthält ein Zeichen, ' +
    'das der Compiler ablehnt (wie E2038): typografische Anführungszeichen aus einer Webseite oder Textverarbeitung, die ASCII-Zeichen ! \" ? \\ ` | ~ sowie Satz- und Sonderzeichen und Emoji jenseits von A' +
    'SCII. Buchstaben, Ziffern und Verbinder wie U+203F bleiben in Bezeichnern erlaubt; asm-Blöcke und {$IF…}-Zweige werden übersprungen; Steuer-, Format- und Leerzeichen melden control-char und invisible-' +
    'char. Schnellkorrektur: ein Paar Anführungszeichen auf einer Zeile wird zum String; ein einzelnes Zeichen mit eindeutigem ASCII-Gegenstück (– − × ÷ ≤ ≥ ≠, Vollbreiten-ASCII) wird ersetzt. Eine UTF-32-' +
    'Datei hat keine Schnellkorrektur; als UTF-8 mit BOM speichern."',
    '    },',
    '{',
    '      "id": "operator-declaration-invalid",',
    '      "name": "Operator falsch deklariert",',
    '      "description": "Ein class operator in einem Record ist so deklariert, wie Delphi es ablehnt: unbekannter Operatorname (wie E2393), falsche Parameterzahl (E2517), eigener Typ fehlt in den Paramet' +
    'ern (E2518) bzw. bei Implicit/Explicit in Parametern und Ergebnis (E2521), Inc/Dec mit anderem Ergebnistyp als dem ersten Parameter (E2519) oder Assign, dessen erster Parameter kein var-Parameter des ' +
    'eigenen Typs ist (E2464, E2617). Rümpfe eines unbekannten Operators oder eines class operator in einer Klasse passen zu keiner Deklaration (E2037). In Klassen, Interfaces und object-Typen lehnt Delphi' +
    ' 13 jeden class operator ab; das meldet die Regel syntax (E2123). Typen gelten als gleich, wenn ihre Namen ohne Unit-Präfix und Typargumente übereinstimmen; Aliase des eigenen Typs in der Datei halten' +
    ' die Regel still, True, False und OnesComplement gelten als bekannt. Vergleichsoperatoren mit anderem Ergebnis als Boolean übersetzt dcc (Spring4D-Kriterien); sie bleiben still. Korrekturen: nächstlie' +
    'gender Operatorname, Ergebnis wie der erste Parameter, var vor dem ersten Parameter, Parameterliste nach Vorlage; jeweils in Deklaration und Rumpf."',
    '    },',
    '{',
    '      "id": "type-restriction-violated",',
    '      "name": "Sprachregel für Records, Inline und Helfer verletzt",',
    '      "description": "Feste Sprachregeln, die erst der Compiler meldet: virtuelle Methoden (wie E2379) oder andere virtuelle Direktiven (override, abstract, reintroduce, message, final; E2463) in Reco' +
    'rds, parameterlose Konstruktoren (E2394), Konstruktoren, deren Parameter alle Vorgabewerte haben (E2471), und Destruktoren (E2465) in Records, Klassenmethoden in Records ohne static (E2398); in Record' +
    '-Helfern virtuelle Methoden (E2598) und die übrigen virtuellen Direktiven (E2475); Felder in Helfern (class var ist erlaubt, E2599), ein Destruktor in einem Class-Helfer (E2295; Klassenkonstruktoren u' +
    'nd Helfer-Konstruktoren ohne Konstruktoraufruf übersetzt dcc, Skia4Delphi), ein Class-Helfer mit Vorfahr-Helfer für einen Typ, der nicht vom Typ des Vorfahren abstammt (E2294, nur bei bekannter Vorfah' +
    'renkette), ein Helfer als Typ einer Deklaration (E2527) oder in einem generischen Typ (E2589); mehrere Klassenkonstruktoren (E2359, sich ausschließende bedingte Zweige zählen einmal), Klassenkonstrukt' +
    'oren mit Parametern (E2360) oder virtual, dynamic bzw. message (E2534); Methoden, Properties, Klassenmitglieder, Typen und Konstanten in lokalen oder anonymen Records (E2433 bis E2437); inline an virt' +
    'uellen oder dynamischen Methoden (E2425), an Konstruktoren und Destruktoren (E2442), mit offenen Array-Parametern (E2439), mit asm-Rumpf (E2426), im interface-Teil deklariert mit Variablen oder typisi' +
    'erten Konstanten des implementation-Teils (E2441; echte Konstanten, Aufzählungswerte, Typen und Routinen übersetzt dcc, mORMot2, Clipper2, dcc-Lauf vom 29.10.2026), als lokale Routine mit Zugriff auf ' +
    'Variablen der umgebenden Routine (E2449) oder mit Aufruf eigener lokaler Routinen (E2501); lokale, absolute oder initialisierte threadvar (E2189, E2190, E2194). Die Prüfungen gelten für alle unterstüt' +
    'zten Delphi-Versionen (10 Seattle bis 13). Option disabledChecks nimmt einzelne Codes aus. Korrekturen: Direktive entfernen, static ergänzen.",',
    '      "options": [',
    '        {',
    '          "name": "disabledChecks",',
    '          "description": "Compilercodes, die die Regel nicht prüft, z. B. [\"E2425\"]."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "inherited-constructor-after-try",',
    '      "name": "Geerbter Konstruktor erst im try-Block",',
    '      "description": "Ein Konstruktor betritt einen try-Block, bevor er den geerbten Konstruktor aufgerufen hat (wie H2505). Self ist dort noch nicht initialisiert; eine Exception im Block kann auf ha' +
    'lb erzeugte Felder treffen. Als geerbter Konstruktor gilt inherited ohne Namen, mit dem Namen des Konstruktors oder mit einem Namen, der mit Create beginnt. Zweige von {$IFDEF} werden getrennt geprüft' +
    '. Korrektur, wenn der Aufruf die erste Anweisung im try-Block ist: vor try ziehen."',
    '    },',
    '{',
    '      "id": "guid-syntax-invalid",',
    '      "name": "GUID mit falscher Schreibweise",',
    '      "description": "Die GUID eines Interfaces oder einer typisierten TGUID-Konstante hat nicht die Form ''{8-4-4-4-12}'' (wie E2204): fehlende Klammern, falsche Zahl oder Länge der Blöcke, Zeichen, di' +
    'e keine Hexadezimalziffern sind, oft nach Hand-Bearbeitung. Geprüft werden nur einzelne Literale; Verkettungen und Konstanten bleiben still. Korrekturen: neue GUID erzeugen; fehlen nur die Klammern, s' +
    'ie ergänzen. Ergänzt interface-guid und duplicate-interface-guid."',
    '    },',
    '{',
    '      "id": "unused-private-member",',
    '      "name": "Privates Mitglied wird nie verwendet",',
    '      "description": "Ein private- oder strict-private-Feld, eine Methode, Konstante oder Property kommt in der Unit nirgends vor (wie H2219, das der Compiler nur für Methoden meldet; Felder ebenso, a' +
    'ußer includeFields ist aus). Jedes Vorkommen des Namens als Bezeichner zählt als Verwendung, auch in inaktiven bedingten Zweigen und hinter read/write; Deklarationen und Methodenköpfe zählen nicht. Au' +
    'sgenommen: Methoden mit message, virtual, dynamic, override oder abstract, Methoden von Typen, die Interfaces umsetzen, Konstruktoren und Destruktoren, Mitglieder mit Attributen (RTTI), Namen aus der ' +
    'Formulardatei und Units mit Include-Dateien. Korrektur: Deklaration (samt ///-Doku) und den Rumpf einer Methode entfernen; nicht, wenn sich mehrere Mitglieder die Deklaration teilen oder die Methode ü' +
    'berladen ist.",',
    '      "options": [',
    '        {',
    '          "name": "includeFields",',
    '          "description": "Auch nie verwendete private Felder melden (der Compiler meldet nur Methoden)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "message-method-invalid",',
    '      "name": "message-Methode falsch deklariert",',
    '      "description": "Eine message-Prozedur einer Klasse hat nicht genau einen var-Parameter (wie E2138; der Typ wird nicht geprüft, ein untypisierter var-Parameter ist in Ordnung), ihre Nachrichtennu' +
    'mmer ist kleiner als 1 (wie E2139) oder eine frühere message-Methode derselben Klasse behandelt schon dieselbe Nummer (wie E2140, meist nach Kopieren). Nummern gelten als gleich, wenn ihre Werte bekan' +
    'nt sind (Zahlen, Konstanten aus dem Index) oder die Ausdrücke gleich lauten. Methoden in sich ausschließenden {$IF}-Zweigen sind nicht doppelt; dieselbe Nummer in einem Nachfahren überschreibt den Han' +
    'dler und ist erlaubt. Korrektur für E2138: einen einzelnen Parameter zu var machen, sonst die Liste durch (var Msg: TMessage) ersetzen; der Rumpf in derselben Datei wird mit angepasst."',
    '    },',
    '{',
    '      "id": "calling-convention-required",',
    '      "name": "Aufrufkonvention passt nicht",',
    '      "description": "Der Compiler schreibt hier die Aufrufkonvention vor: Konstruktoren und Destruktoren einer Klasse nur mit register (wie E2236), Getter und Setter von published-Properties ebenso (' +
    'wie E2270) und varargs nur mit cdecl (wie E2277 bei external-Routinen, sonst E2591); ohne external ist varargs unter Win32 gar nicht erlaubt (wie E2277), was die Regel nur bei bekannter Plattform meld' +
    'et. Ein ausdrückliches register ist in Ordnung; Klassenkonstruktoren, Accessoren außerhalb von published-Abschnitten und geerbte Accessoren bleiben still. Korrektur: die Konvention in der Deklaration ' +
    'und im Rumpf derselben Datei entfernen bzw. bei varargs cdecl setzen."',
    '    },',
    '{',
    '      "id": "automation-invalid",',
    '      "name": "OLE-Automation falsch deklariert oder aufgerufen",',
    '      "description": "Deklarationen, die der Compiler im Abschnitt automated einer Klasse ablehnt: Felder (wie E2175), Konstruktoren und Destruktoren (wie E2177), dynamic- und message-Methoden (wie E2' +
    '178), andere Aufrufkonventionen als register (wie E2179), dieselbe dispid zweimal in einer Klasse (wie E2180), eine Property, die ohne Typ neu deklariert wird (wie E2181), index, stored, default und n' +
    'odefault an Properties (wie E2182), read oder write auf ein Feld der Klasse (wie E2096), eine dispid an einer override-Methode (wie E2185) sowie Records, Zeiger und Mengen als Typ von Parametern, Erge' +
    'bnissen und Properties (wie E2176). Eine dispid an einer Methode außerhalb von automated meldet die Regel wie Delphi 13 als E2185 (dokumentiert ist E2183). Aufrufe über Variant oder OleVariant (V.Oeff' +
    'nen(...), auch V.Dokument.Oeffnen(...)): ein Record ohne Operatoren oder ein Zeiger als Argument (wie E2160 bei OleVariant, wie E2281 bei Variant) und ein unbenanntes Argument nach einem benannten (wi' +
    'e E2166). Mitglieder in bedingten Zweigen und Typen, die die Namensauflösung nicht sicher kennt, bleiben still. Dass automated selbst veraltet ist, meldet deprecated-symbol."',
    '    },',
    '{',
    '      "id": "dispinterface-invalid",',
    '      "name": "dispinterface-Deklaration unzulässig",',
    '      "description": "Ein dispinterface verletzt eine seiner festen Regeln: kein Vorfahr in Klammern (wie E2228), eine GUID ist Pflicht (wie E2229), Methoden tragen keine Direktiven außer dispid und d' +
    'en Hinweisen deprecated, platform, library und experimental (wie E2230; gemeldet werden Aufrufkonventionen und Bindungsdirektiven wie virtual, overload bleibt still) und Properties kein read oder writ' +
    'e (wie E2231; stattdessen readonly, writeonly oder dispid). Vorwärtsdeklarationen und Deklarationen in bedingten Zweigen bleiben still. Korrekturen: Vorfahren entfernen, GUID einfügen, Direktive entfe' +
    'rnen."',
    '    },',
    '{',
    '      "id": "abstract-declaration-invalid",',
    '      "name": "abstract, final oder static falsch kombiniert",',
    '      "description": "Eine Methodendirektive, die der Compiler ablehnt: abstract ohne virtual, dynamic oder override (wie E2167), ein Rumpf im implementation-Teil zu einer abstrakten Methode (wie E213' +
    '6), final an einer nicht virtuellen Methode (wie E2351), abstract zusammen mit final (wie E2371), eine Klasse abstract sealed (wie E2540), eine abstrakte Methode in einer sealed-Klasse (wie E2383, E25' +
    '40) oder eine sealed-Klasse, die eine geerbte abstrakte Methode offen lässt (wie E2539, Vorfahren über den Symbolindex) oder static an einer Instanzmethode bzw. einer virtuellen Klassenmethode (wie E2' +
    '376). Ein Rumpf zählt nur dann als Rumpf einer abstrakten Methode, wenn keine gleichnamige nicht abstrakte Methode derselben Klasse mit ihm übersetzt wird (Überladungen, {$IFDEF}-Zweige). Korrekturen:' +
    ' virtual; vor abstract einfügen, Rumpf entfernen."',
    '    },',
    '{',
    '      "id": "unsatisfied-forward",',
    '      "name": "Vorwärtsdeklaration nie aufgelöst",',
    '      "description": "Eine Routine aus dem interface-Teil oder mit forward hat keinen Rumpf (wie E2065), oder eine Vorwärtsdeklaration TFoo = class; bzw. IFoo = interface; wird im selben type-Abschnit' +
    't nie vollständig deklariert (wie E2086, E2420). Ein Record, der sich selbst als Feld enthält, und eine Klasse oder ein Interface, die einen erst vorwärts deklarierten Typ als Vorfahr oder in der Inte' +
    'rface-Liste nutzen, verwenden ebenfalls einen unvollständigen Typ (wie E2086). Methoden prüft declared-not-implemented. Ein Rumpf passt, wenn er gleich heißt; bei overload muss auch die Zahl der Param' +
    'eter stimmen. Ein external im implementation-Teil zählt als Rumpf. Deklarationen in einem {$IFDEF}-Zweig bleiben unbeachtet; mit Include-Dateien prüft die Regel keine Routinen. Korrektur: leeren Rumpf' +
    ' vor initialization bzw. dem abschließenden end. anlegen."',
    '    },',
    '{',
    '      "id": "directive-typo",',
    '      "name": "Unbekannte Direktive (Tippfehler)",',
    '      "description": "An der Stelle einer Direktive steht ein Wort, das keine ist: nach dem '';'' eines Routinen- oder Methodenkopfs (overide;, virutal;, overlaod;, stdcal;, reintroduces;) oder nach ein' +
    'er Property, wo nur default erlaubt ist (defualt;). Der Compiler bricht dort ab (wie E2070). Die Meldung schlägt die ähnlichste Direktive vor, wenn höchstens zwei Zeichen abweichen. Still in {$IF}-Zwe' +
    'igen, die FPC abfragen; FPC kennt weitere Direktiven wie nostackframe. Korrektur: durch die vorgeschlagene Direktive ersetzen."',
    '    },',
    '{',
    '      "id": "default-parameter-invalid",',
    '      "name": "Unzulässiger Standardwert eines Parameters",',
    '      "description": "Standardwerte, die der Compiler ablehnt: mehrere Namen mit einem gemeinsamen Standardwert (A, B: Integer = 0, wie E2237), ein Parameter ohne Standardwert nach einem mit Standardw' +
    'ert (wie E2238), var- und out-Parameter mit Standardwert (wie E2239) Records oder statische Arrays mit Standardwert (wie E2268) sowie Mengen über 4 Byte mit Standardwert (wie E2146, erlaubt sind nur k' +
    'leine Mengen; mittlere Konfidenz). Gilt für Routinen, Methoden und Prozedurtypen. Korrekturen: Parameter einzeln deklarieren; Parameter mit Standardwert ans Ende verschieben, auch im zugehörigen Kopf ' +
    'der Deklaration bzw. Implementierung derselben Datei (Aufrufe ändert sie nicht)."',
    '    },',
    '{',
    '      "id": "jump-outside-allowed-scope",',
    '      "name": "Break, Continue oder Exit an unzulässiger Stelle",',
    '      "description": "Break oder Continue außerhalb einer Schleife (wie E2097) bzw. Break, Continue oder Exit, die einen finally-Block verlassen (wie E2126). Delphi meldet beides erst beim Übersetzen;' +
    ' häufig nach dem Herausziehen eines Schleifenrumpfs in eine eigene Methode. Eine Schleife ganz im finally-Block darf Break und Continue verwenden. Routinen und anonyme Methoden beginnen neu: Ein Break' +
    ' in einer anonymen Methode gehört nicht zur Schleife um sie herum. Gemeldet werden nur einfache Aufrufe (nicht TMonitor.Exit(FLock)) und nicht, wenn die Datei eine Routine oder Variable dieses Namens ' +
    'deklariert. Korrektur außerhalb eines finally-Blocks: Break durch Exit ersetzen."',
    '    },',
    '{',
    '      "id": "reraise-outside-handler",',
    '      "name": "raise ohne Argument außerhalb eines Handlers",',
    '      "description": "raise; ohne Exception-Objekt ist nur in einem except-Block erlaubt (wie E2145); Delphi meldet es erst beim Übersetzen. Es passiert in einer lokalen Prozedur, die aus dem Handler ' +
    'gerufen wird, in einem finally-Block oder nach dem Verschieben von Code. Routinen und anonyme Methoden beginnen neu. Still bleibt die Regel in anonymen Methoden innerhalb eines except-Blocks und in Ro' +
    'utinen, in denen der Parser einen Fehler meldet. Keine Korrektur: eine neue Exception auslösen (raise EImport.Create(…)) oder den Code in den Handler verschieben. raise E; im Handler meldet reraise-ex' +
    'ception-object."',
    '    },',
    '{',
    '      "id": "label-misuse",',
    '      "name": "Sprungmarke falsch verwendet",',
    '      "description": "Eine Marke ist doppelt gesetzt (wie E2073), deklariert und angesprungen, aber nie gesetzt (E2074), gesetzt oder angesprungen, ohne in der aktuellen Routine deklariert zu sein (E2' +
    '093; ein goto auf eine nirgends deklarierte und nie gesetzte Marke meldet die Regel syntax als E2031), oder goto springt in einen try-Block hinein oder aus ihm heraus, auch zwischen try-Teil und excep' +
    't bzw. finally (E2127). Delphi meldet das erst beim Übersetzen. Marken gehören zu einer Routine bzw. zum Programmblock; eine lokale Prozedur kann keine Marke der umgebenden Routine anspringen. Doppelt' +
    'e Marken in bedingten Zweigen, die sich ausschließen, bleiben still, ebenso Routinen mit asm-Block, weil Marken im asm nicht im Syntaxbaum stehen. Keine Korrektur."',
    '    },',
    '{',
    '      "id": "for-variable-misuse",',
    '      "name": "Schleifenvariable verändert oder nicht lokal",',
    '      "description": "Der Variablen einer for-Schleife wird im Rumpf zugewiesen oder sie wird mit Inc/Dec verändert (wie E2081), sie wird als var- bzw. out-Parameter an eine Routine dieser Datei überg' +
    'eben (wie W1015) oder sie ist keine einfache lokale Variable: Feld der eigenen Klasse oder lokale Variable der umgebenden Routine (wie E1019) bzw. globale Variable der Unit (wie W1019, Delphi warnt nu' +
    'r). Delphi meldet das erst beim Übersetzen. Parameter, unbekannte Namen und Schleifen in with-Anweisungen bleiben still, ebenso anonyme Methoden im Rumpf und Routinen mit Parserfehlern. Korrekturen: a' +
    'uf eine while-Schleife umstellen (nicht bei Continue im Rumpf) bzw. for var verwenden, wenn die Routine den Namen sonst nicht benutzt."',
    '    },',
    '{',
    '      "id": "for-variable-after-loop",',
    '      "name": "Schleifenvariable nach der Schleife gelesen",',
    '      "description": "Nach einer for-Schleife, die normal endet (ohne Break), ist die Schleifenvariable undefiniert. Die Regel meldet das erste Lesen der Variable auf einem Weg vom normalen Schleifene' +
    'nde, bevor ihr erneut zugewiesen wird (wie W1037). Geprüft werden nur einfache lokale Variablen der Routine; for var, Felder, globale Variablen, Lesen nur im Rumpf, Argumente von Routinen, die out-Par' +
    'ameter sein könnten, und Routinen mit unvollständigem Ablaufgraphen bleiben still. Korrektur: auf eine while-Schleife umstellen, deren Zähler danach einen festen Wert hat."',
    '    }');

implementation

end.
