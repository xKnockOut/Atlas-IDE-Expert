unit Atlas.Common.Rules.Catalog.Data.De.CompilerNames;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeCompilerNames: array[0..217] of string = (
    '{',
    '      "id": "deprecated-symbol",',
    '      "name": "Veraltetes oder gebundenes Symbol",',
    '      "description": "Eine Routine, ein Typ, eine Konstante oder ein Mitglied mit deprecated, experimental, platform oder library wird verwendet (wie W1000, W1003, W1002, W1001), oder eine Unit, deren' +
    ' Kopf einen dieser Hinweise trägt, steht in uses (wie W1006, W1007, W1005, W1004); auch der veraltete Abschnitt automated einer Klasse zählt als veraltetes Symbol (wie W1000). Gemeldet wird nur, was s' +
    'icher aufgelöst ist. Der Editor streicht veraltete Namen durch; die Meldung nennt den Grund aus deprecated ''Grund''. Die Deklaration und der Kopf ihrer Implementierung werden nicht gemeldet. Ob eine Ar' +
    't gemeldet wird, folgt wie bei dcc dem Stand der Warnung: ab Werk sind alle acht an, dann gilt die Projektoption der .dproj (DCC_SYMBOL_PLATFORM = false usw.), dann die Schalter {$WARN SYMBOL_DEPRECAT' +
    'ED OFF|ON|ERROR|DEFAULT}, {$WARN UNIT_PLATFORM …} usw. und {$WARNINGS OFF} ab ihrer Stelle; ein Schalter in einem {$IF}-Zweig, der nicht sicher mit übersetzt wird, hält die Stelle still. Die Option ki' +
    'nds schränkt die Arten zusätzlich ein. Die .NET-Direktive {$UNSAFECODE ON|OFF} meldet die Regel wie ein plattformspezifisches Symbol (wie W1002), so wie dcc für Windows. Korrektur: durch den Namen aus' +
    ' dem Grund ersetzen (bei IncludeTrailingBackslash und ExcludeTrailingBackslash durch die plattformunabhängige Routine), wenn genau ein Name passt, an der Stelle sichtbar ist und dieselbe Art hat. Ohne' +
    ' Projektindex prüft die Regel nur die Symbole der Datei selbst.",',
    '      "options": [',
    '        {',
    '          "name": "kinds",',
    '          "description": "Gemeldete Arten: deprecated, experimental, platform, library (Standard alle vier; eine im Projekt oder in der Datei abgeschaltete Warnung bleibt ohnehin still)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "signature-mismatch",',
    '      "name": "Implementierung weicht von der Deklaration ab",',
    '      "description": "Der Kopf im implementation-Teil hat andere Parameter (Anzahl, Name, Typ, const/var/out), einen anderen Ergebnistyp, procedure statt function oder eine andere Aufrufkonvention als' +
    ' die Deklaration im Typ oder, bei einer Routine der Unit, im interface-Teil (wie E2037). Bei Überladungen wird die nächstliegende Deklaration verglichen (Parameteranzahl, dann Typen, Namen und Modifiz' +
    'ierer); ist sie nicht eindeutig, melden declared-not-implemented und implemented-not-declared beide Seiten. Routinen der Unit vergleicht die Regel nur bei eindeutigem Namen und ohne overload, external' +
    ' und forward. Ein Rumpf darf Parameterliste, Ergebnistyp und Aufrufkonvention weglassen. Methoden in {$IF}-Blöcken werden übergangen; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Kopf der ' +
    'Implementierung an die Deklaration angleichen oder als zweite Aktion die Deklaration an die Implementierung (Standardwerte bleiben in der Deklaration). refactoring.syncSignatures = false entfernt nur ' +
    'die Korrekturen."',
    '    },',
    '{',
    '      "id": "interface-not-implemented",',
    '      "name": "Interface-Methode fehlt in der Klasse",',
    '      "description": "Eine Klasse nennt ein Interface, implementiert aber nicht alle seine Methoden, auch die der Vorfahr-Interfaces (wie E2291). Eine gleichnamige Methode der Klasse mit anderer Signa' +
    'tur wird an dieser Methode gemeldet (wie E2211). Geerbte Methoden der Vorfahrklassen, Methodenzuordnungen (procedure IFoo.Bar = Baz) und Properties mit implements zählen; ebenso die öffentlichen Metho' +
    'den von TObject und die IInterface-Methoden von TInterfacedObject und ähnlichen RTL-Basen. Endet die Kette der Vorfahrklassen bei einer unbekannten Klasse oder ist das Interface unbekannt, bleibt die ' +
    'Regel still. Gemeldet wird auch eine Methodenzuordnung für ein Interface, das die Klasse nicht nennt (wie E2265). Klassen in {$IF}-Blöcken werden übergangen. Korrektur: fehlende Methoden deklarieren u' +
    'nd leer implementieren (nicht bei abweichendem Kopf)."',
    '    },',
    '{',
    '      "id": "uses-unit-not-found",',
    '      "name": "Unit in uses nicht gefunden",',
    '      "description": "Eine Unit aus uses oder contains liegt weder im Projekt noch in den Ordnern, die der Compiler durchsucht: Ordner der verwendenden Datei, Projektordner, Suchpfade und DCU-Ausgabeo' +
    'rdner der .dproj, Bibliothekspfade der Installation, jeweils als .pas oder .dcu und mit jedem Unit-Namespace davor (SysUtils → System.SysUtils); bei Packages zusätzlich die Units der requires-Packages' +
    ' (wie F2613). Ebenso gemeldet: eine Datei aus in ''…'', die es nicht gibt (F1026, auch ohne Projekt, denn es zählt nur der Pfad relativ zur verwendenden Datei), ein Package aus requires, das weder als .' +
    'dpk noch als .dcp gefunden wird (E2202), eine Unit, die sich selbst einbindet (F2092), und einmal eine fehlende Unit System, also ein fehlender Bibliothekspfad, statt einer Meldung je Unit (F1027). Ei' +
    'nträge in {$IF}-Blöcken werden übergangen; ohne bekannte Installation, mit offenem Makro in einem Suchpfad oder einem requires-Package mit unbekanntem Inhalt bleibt die Regel still. Die Meldung nennt ' +
    'ähnliche Units. Korrekturen: die Unit mit Namespace (Forms → Vcl.Forms) bzw. eine ähnlich geschriebene einsetzen oder den Ordner unter dem Projekt, in dem die Unit liegt, in DCC_UnitSearchPath der Bas' +
    'iskonfiguration der .dproj aufnehmen.",',
    '      "options": [',
    '        {',
    '          "name": "searchPaths",',
    '          "description": "Wo Units gesucht werden: project (wie der Compiler: Projekt, Suchpfade der .dproj, Bibliothekspfade, .pas und .dcu), atlas (was Atlas kennt: Index und Quellpfade der Installa' +
    'tion) oder both."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unresolved-attribute",',
    '      "name": "Attribut nicht gefunden und still ignoriert",',
    '      "description": "Ein Attribut [Name] lässt sich weder einer Klasse NameAttribute noch Name zuordnen, meist weil eine Unit in uses fehlt. Delphi warnt nur (W1074, nach {$WARN UNKNOWN_CUSTOM_ATTRIB' +
    'UTE ERROR} E1074) und übergeht das Attribut: DUnitX-Tests laufen dann nicht, JSON- oder ORM-Zuordnungen fehlen. Die Meldung nennt die Unit, die das Attribut im Index deklariert; eine Fassaden-Unit, di' +
    'e den Typ aus einer anderen Kandidatin weiterreicht (DUnitX.TestFramework statt DUnitX.Attributes), geht vor, und die DUnitX-Attribute sind auch ohne DUnitX im Index bekannt. Attribute des Compilers w' +
    'ie Weak, Unsafe, Ref und Volatile zählen immer. Still ohne die Unit System im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das Attribut deklarieren), in {$IF}-Blöcken und bei unbeka' +
    'nntem Vorfahren der umgebenden Klasse; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Unit in uses aufnehmen."',
    '    },',
    '{',
    '      "id": "duplicate-case-label",',
    '      "name": "Doppelte case-Marke",',
    '      "description": "Zwei Marken einer case-Anweisung decken denselben Wert ab (wie E2030), auch über Bereiche (1..5 und 3), Konstanten mit gleichem Wert, Zeichen (''a'' und #97) und Bereiche von Aufzä' +
    'hlungswerten. Gleiches gilt für die Marken eines varianten Record-Teils (wie E2027). Die Werte ergeben sich aus Zahlen, Zeichen, Konstanten und Aufzählungswerten über die Namensauflösung; Marken mit u' +
    'nbekanntem Wert vergleicht die Regel nur über den Text. Gemeldet wird eine Marke nur, wenn die frühere immer mit übersetzt wird: verschiedene Zweige desselben {$IF} stoßen nie zusammen. Korrektur: den' +
    ' doppelten Wert aus dem späteren Zweig entfernen bzw. den ganzen Zweig, wenn es seine einzige Marke war; eine teilweise Überschneidung von Bereichen meldet die Regel ohne Korrektur."',
    '    },',
    '{',
    '      "id": "override-target-missing",',
    '      "name": "override ohne passende virtuelle Methode",',
    '      "description": "Eine Methode mit override, zu der kein Vorfahr eine virtuelle (oder dynamic, abstract) Methode mit gleichem Namen und gleichen Parametern hat (wie E2137): oft ein Tippfehler (Des' +
    'tory) oder im Vorfahren geänderte Parameter. Die Meldung nennt die nächstliegende virtuelle Methode des Vorfahren („dort heißt es Ausfuehren(const Modus: TModus)“) bzw. einen ähnlichen Namen. Außerdem' +
    ': override auf eine statische Methode (wie E2170), auf eine finale (wie E2352) und Ableiten von einer sealed-Klasse (wie E2353). Vorfahren sucht die Regel in der Datei und im Symbolindex; bricht die K' +
    'ette an einer unbekannten Klasse ab, bleibt sie still. Ohne System im Index gelten die virtuellen Methoden von TObject als vorhanden. Typparameter generischer Vorfahren, Typaliase und Synonyme wie Lon' +
    'gint passen. Korrektur: Signatur des Vorfahren in Deklaration und Implementierung übernehmen."',
    '    },',
    '{',
    '      "id": "abstract-class-instantiated",',
    '      "name": "Instanz einer Klasse mit abstrakten Methoden",',
    '      "description": "Create auf einer Klasse, die abstrakte Methoden deklariert oder erbt, ohne sie zu überschreiben (wie W1020). Eine als abstract deklarierte Klasse ohne abstrakte Methoden lässt si' +
    'ch erzeugen; dcc setzt \"class abstract\" nicht durch (E2402 gibt es nur unter .NET, #1383). Der Aufruf einer abstrakten Methode löst zur Laufzeit EAbstractError aus; die Meldung nennt die offenen Met' +
    'hoden. Klassen sucht die Regel in der Datei und im Symbolindex; Überladungen mit gleicher Parameterzahl gelten als eine Methode. Aufrufe über Klassenreferenzen, inherited Create und Konstruktor-Rümpfe' +
    ' prüft sie nicht. Korrektur für eine Klasse dieser Datei, die die abstrakten Methoden erbt: dort überschreiben (wie die Code-Aktion „überschreiben“)."',
    '    },',
    '{',
    '      "id": "property-accessor-invalid",',
    '      "name": "Getter oder Setter einer Property ungültig",',
    '      "description": "Der Name hinter read oder write einer Property passt nicht: Er ist weder in der Klasse noch in ihren Vorfahren deklariert oder ist eine Property (wie E2168); Getter oder Setter h' +
    'aben die falsche Art, Parameter oder Typen (wie E2008, ältere Delphi-Versionen E2234); der Setter nimmt einen var- oder out-Parameter (wie E2282); die Zugriffsmethode ist überladen, und keine Überladu' +
    'ng passt (wie E2250, ältere Delphi-Versionen E2271); eine Klassen-Property nutzt ein Instanzmitglied oder eine Klassenmethode ohne static (wie E2355), eine Instanz-Property eine class var oder eine st' +
    'atische Klassenmethode (wie E2356); eine Array-Property nutzt ein Feld (wie E2008 in Delphi 13, dokumentiert als E2174, index mit Feld übersetzt dcc); ein Feldselektor geht über ein Feld, das kein Rec' +
    'ord ist, oder steht hinter einer Klassen-Property (wie E2459), nennt ein Mitglied, das kein Feld ist (wie E2461), oder ein Feld, das dem Record fehlt (wie E2562). Namen sucht die Regel in der Datei un' +
    'd für Vorfahren im Symbolindex; sie bleibt still, wenn die Kette der Vorfahren abbricht, der Name nur in einem inaktiven Zweig steht, die Klasse ihn nicht sieht oder Include-Dateien einbindet. Typen v' +
    'ergleicht sie nur, wenn beide eingebaut oder als eigener Typ deklariert sind. Korrektur für ein fehlendes F<Name>, Get<Name> oder Set<Name>: anlegen (wie die Vervollständigung hinter read/write, compl' +
    'etion.accessorSection)."',
    '    },',
    '{',
    '      "id": "unit-name-conflict",',
    '      "name": "Unit-Name kollidiert",',
    '      "description": "Eine Unit heißt wie eine für den Compiler reservierte Unit, System oder SysInit (wie E2272), oder {$NOINCLUDE X} nennt eine Unit, die der Compiler nicht kennt (wie E2242); dafür ' +
    'braucht die Regel die Unit-Suche des Projekts und schweigt ohne sichere Antwort. Die Quellen der RTL (source/rtl) prüft sie nicht. Nicht gemeldet: E2447, W1051 und X2421 gehören zu den Namensräumen de' +
    'r .NET-Metadaten, die dcc32/dcc64 nicht erzeugt; für E2399 nennt die Dokumentation keine Bedingung, und eine Unit Kunden neben Kunden.Daten übersetzt Delphi ohne Fehler (Spring.pas neben Spring.Collec' +
    'tions.pas). Schnellkorrektur für {$NOINCLUDE}: eine ähnlich geschriebene bekannte Unit einsetzen."',
    '    },',
    '{',
    '      "id": "implicit-variants-unit",',
    '      "name": "Variant ohne System.Variants in uses",',
    '      "description": "Die Unit verwendet Variant oder OleVariant als Typ, ohne System.Variants in uses zu haben. Der Compiler bindet die Unit dann still ein (wie W1040) und ändert damit die Initialisi' +
    'erungsreihenfolge. Die Regel zählt Typangaben im Syntaxbaum (Variablen, Felder, Parameter, Ergebnisse, Typargumente); Variants in uses gilt auch in einem {$IF…}-Zweig und ohne Namespace. Still in Syst' +
    'em, SysInit und Variants selbst, wenn die Datei einen eigenen Typ Variant deklariert, und nach {$WARN IMPLICIT_VARIANTS OFF}. Standardmäßig aus (Profil strict). Schnellkorrektur: System.Variants in us' +
    'es aufnehmen (Variants, wenn die Unit SysUtils oder Classes ohne Namespace nennt)."',
    '    },',
    '{',
    '      "id": "anonymous-capture-invalid",',
    '      "name": "Anonyme Methode erfasst, was sie nicht erfassen darf",',
    '      "description": "Eine anonyme Methode greift auf einen var-, out- oder untypisierten Parameter oder auf Result einer umgebenden Routine bzw. anonymen Funktion zu (wie E2555). Der Name wird von in' +
    'nen nach außen aufgelöst (Parameter, var/const/type, lokale Routinen, Inline-Variablen, for var); in with und asm bleibt die Regel still, Deklarationen in Zweigen bedingter Übersetzung, die die Stelle' +
    ' ausschließen, zählen nicht. Korrektur: Wert vor der Anweisung in eine lokale Variable kopieren, in der anonymen Methode nur diese verwenden und nach der Anweisung zurückschreiben, wenn die Methode si' +
    'e zuweist."',
    '    },',
    '{',
    '      "id": "generic-declaration-invalid",',
    '      "name": "Generische Deklaration unzulässig",',
    '      "description": "Eine generische Deklaration, die Delphi ablehnt: Einschränkungen class und record zugleich (wie E2507), eine Einschränkung doppelt (E2603), record zusammen mit constructor (E2516' +
    '), eine Klasse neben class bzw. record (E2552), zwei Klassen (E2553), ein Einschränkungstyp, der weder Klasse noch Interface ist (E2510); Typparameter an Aufzählung, Menge, Teilbereich, Zeiger, Klasse' +
    'nreferenz, Alias oder Helfer (E2508), an Konstruktor einer Klasse, Destruktor oder Klassenkonstruktor (E2528), Operator (E2529), globaler Routine (E2530), virtueller, dynamischer, message- oder overri' +
    'de-Methode (E2533) oder Interface-Methode (E2535); class of eines parametrisierten Typs (E2548), generische Klasse, die von TCustomAttribute erbt (E2549), parametrisierter Typ als Attribut (E2565); ei' +
    'n Typparameter, der einen des umgebenden Typs verdeckt (H2509); ein Aufruf mit einer Zahl Typargumente, die keine Überladung hat (E2551, Klassen und Records der Datei mit Vorfahren aus der Datei); ein' +
    'e Methode eines generischen Typs oder eine generische Methode aus dem interface-Teil, die ein Symbol des implementation-Teils verwendet (E2506; still in with und wenn die Vorfahrenkette nicht bekannt ' +
    'ist); eine lokale Routine in einer generischen Methode oder einer Methode eines generischen Typs (E2570); type vor einem instanziierten Typ wie type TList<Integer> (E2574, Korrektur: type entfernen un' +
    'd einen Alias deklarieren). Typen zählen, wenn sie eingebaut oder in der Datei deklariert sind und, bei Klassen als Einschränkung (E2552, E2553), auch aus dem Symbolindex; unbekannte Typen halten die ' +
    'Regel still."',
    '    },',
    '{',
    '      "id": "attribute-usage-invalid",',
    '      "name": "Attribut falsch verwendet",',
    '      "description": "Ein Attribut des Compilers steht dort, wo Delphi es ablehnt: [Weak] an einem Feld oder einer Variablen, deren Typ sicher weder Klasse noch Interface ist (eingebaute Werttypen, Re' +
    'cords, Aufzählungen, Mengen, Arrays, Zeigertypen der Datei, Aliase verfolgt; wie E2584), [Volatile] an Typ, Routine, Methode oder Property (E2325), Weak, Unsafe, Volatile oder Ref doppelt an derselben' +
    ' Deklaration (E2326; sich ausschließende Zweige zählen nicht) oder ein Attributargument, das sicher eine Variable oder Routine der Datei ist (E2448; vor dem Attribut sichtbar, nicht durch eine gleichn' +
    'amige Konstante, einen Typ oder eine andere Deklaration verdeckt). Eigene Attribute dürfen mehrfach stehen; ein Typ Weak bzw. WeakAttribute in der Datei macht die Regel für diesen Namen still. Keine S' +
    'chnellkorrektur."',
    '    },',
    '{',
    '      "id": "typeinfo-invalid",',
    '      "name": "TypeInfo oder Default mit unzulässigem Argument",',
    '      "description": "TypeInfo oder Default bekommt eine Variable statt eines Typs (wie E2133, E2537: Parameter, lokale, Inline- und Unit-Variablen, Felder, Properties, Result, for- und Ausnahmevariab' +
    'len), TypeInfo einen Typ ohne RTTI (Aufzählung mit festen Werten, Dateityp, Text/TextFile; E2134) oder Default einen Dateityp (E2538; Delphi 13 meldet zur Zuweisung zusätzlich E2015). Namen werden von' +
    ' innen nach außen aufgelöst; in with, in Helfern, in Methoden von Typen außerhalb der Datei, bei Deklarationen in anderen bedingten Zweigen und wenn Datei oder Index ein eigenes TypeInfo bzw. Default ' +
    'deklarieren, bleibt die Regel still. Korrektur: den deklarierten Typ der Variablen einsetzen."',
    '    },',
    '{',
    '      "id": "variant-record-managed-field",',
    '      "name": "Verwalteter Typ im varianten Teil eines Records",',
    '      "description": "Im varianten Teil eines Records (case … of) steht ein String, ein dynamisches Array, ein Interface, ein Variant oder ein Record mit solchen Feldern (wie E2154), ein verwalteter R' +
    'ecord mit class operator Initialize oder Finalize (wie E2418) oder ein Typparameter ohne record-Einschränkung (wie E2569); ebenso hinter file of (wie E2155, E2417). Typen werden in der Datei und im In' +
    'dex aufgelöst; unbekannte bleiben still. Korrekturen: Feld vor case in den festen Teil verschieben, ShortString verwenden oder den Typparameter mit record einschränken."',
    '    },',
    '{',
    '      "id": "type-too-large",',
    '      "name": "Typ überschreitet eine Größengrenze",',
    '      "description": "Ein statisches Array oder Record ist 2 GB groß oder größer (wie E2100), ebenso eine Instanz eines generischen Typs dieser Datei (wie E2543). Atlas rechnet eine untere Grenze aus ' +
    'den Deklarationen: Indexbereiche über konstante Ausdrücke, Konstanten und Aufzählungen der Datei, eingebaute Typen, Records aus dem Index; Unbekanntes zählt 0, gemeldet wird also nur sicher. Gemeldet ' +
    'wird nur der innerste Typ, der die Grenze überschreitet. E2419 (Records über 1 MB) gilt nur für Delphi für .NET und wird nicht gemeldet. Keine Korrektur; stattdessen ein dynamisches Array oder einen Z' +
    'eiger verwenden."',
    '    },',
    '{',
    '      "id": "constant-initializer-mismatch",',
    '      "name": "Initialisierung einer Konstanten passt nicht",',
    '      "description": "Eine typisierte Konstante oder initialisierte Variable vom statischen Array-Typ hat mehr oder weniger Elemente als ihr Indexbereich (wie E2072), typisch nach einem neuen Wert in ' +
    'einer Aufzählung (array[TStatus] of string); geprüft je Dimension und auch für benannte Array-Typen der Datei. Ebenso Record-Konstanten, deren Felder in anderer Reihenfolge als deklariert stehen (wie ' +
    'E2083). Indexbereiche: Teilbereiche mit konstanten Grenzen, Aufzählungen ohne eigene Werte, Boolean, Byte, Char usw. Deklarationen mit bedingten Direktiven gelten als unsicher. Korrekturen: über einer' +
    ' Aufzählung fehlende Einträge an ihrer Stelle ergänzen bzw. überzählige entfernen (erkannt an Texten, Bezeichnern und Kommentaren mit dem Wertnamen; sonst hinten und als geschätzt benannt), neue Strin' +
    'gs mit dem Text aus dem Namen, andere Typen mit Standardwert und Kommentar {TODO Wert} (#667); über anderen Bereichen fehlende Einträge mit Platzhalter ergänzen; Felder in die Reihenfolge der Deklarat' +
    'ion bringen."',
    '    },',
    '{',
    '      "id": "unsafe-code",',
    '      "name": "Unsicherer Code",',
    '      "description": "Code, den dcc seit Delphi für .NET als unsicher meldet: der @-Operator auf eine Variable, ein Feld oder einen Parameter (wie W1047) und die Umwandlung eines untypisierten Pointer' +
    ' in eine Klasse, TObject(P) bzw. TKunde(P) (wie W1048). dcc schaltet diese Warnungen ab Werk ab; die Regel meldet nur, wo sie wie bei dcc an sind: {$WARN UNSAFE_CODE ON} bzw. {$WARN UNSAFE_CAST ON} vo' +
    'r der Stelle oder DCC_UNSAFE_CODE bzw. DCC_UNSAFE_CAST = true in der .dproj; ERROR macht den Treffer zum Fehler, OFF und {$WARNINGS OFF} halten ihn still. @ auf Routinen und Methoden, typisierte Zeige' +
    'r, Umwandlungen als Argument (TObject(Pointer(I))) und Interfaces bleiben still. Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der Stelle übersetzt wird."',
    '    },',
    '{',
    '      "id": "inaccessible-member",',
    '      "name": "Zugriff auf ein nicht sichtbares Mitglied",',
    '      "description": "Zugriff A.B auf ein Mitglied, das an der Stelle nicht sichtbar ist: private bzw. strict private einer anderen Unit oder Klasse (wie E2361), protected bzw. strict protected außerh' +
    'alb der deklarierenden Unit und ihrer Nachfahren (wie E2362, E2389). In einer Klassenmethode oder statischen Methode sind Instanzfelder, -methoden und -Properties der Klasse nicht erreichbar (wie E212' +
    '4). Eine Property, die auf ein private-Mitglied eines Vorfahren derselben Unit verweist, meldet die Regel als Warnung (wie W1045). Gemeldet wird nur, wenn die Namensauflösung den Empfänger und seinen ' +
    'Typ sicher kennt und das Mitglied erst ohne Rücksicht auf die Sichtbarkeit findet; protected-Mitglieder bleiben über eine Klasse der eigenen Unit sichtbar (TZugang(Control).Click). Ein privater Klasse' +
    'nkonstruktor verdeckt kein geerbtes Create, und eine class-Überladung einer Methode bleibt aus einer Klassenmethode erreichbar. protected-Mitglieder über einen generischen Empfänger (TKnoten<T>) übers' +
    'etzt dcc aus generischem Code auch in anderen Units (Spring4D); aus nicht generischem Code meldet dcc E2362. Deklarationen in bedingten Zweigen, Methoden von Helfern und verschachtelten Typen bleiben ' +
    'still."',
    '    },',
    '{',
    '      "id": "interface-declaration-invalid",',
    '      "name": "Unzulässige Deklaration in einem Interface",',
    '      "description": "Ein Interface deklariert etwas, das Interfaces nicht haben dürfen: Felder (wie E2209), Sichtbarkeitsabschnitte oder Methodendirektiven wie virtual, dynamic, abstract, override, m' +
    'essage oder reintroduce (wie E2210), die Property-Klauseln stored, nodefault oder default mit Wert (wie E2207; default; hinter einer Array-Property ist erlaubt) oder eine Property, die ein Vorfahr-Int' +
    'erface schon deklariert, ohne Typ erneut aufgeführt (wie E2206; eine Neudeklaration mit Typ übersetzt dcc, auch mit geerbten Accessoren). Ebenso gemeldet werden eine Klasse, ein Record oder eine Aufzä' +
    'hlung als Vorfahr eines Interfaces oder in der Interface-Liste einer Klasse (wie E2205) und dasselbe Interface zweimal in dieser Liste (wie E2208). Typen werden über die uses-Klauseln aufgelöst; Alias' +
    'e, unbekannte Typen, dispinterface und Deklarationen in bedingten Zweigen bleiben still."',
    '    },',
    '{',
    '      "id": "implements-clause-invalid",',
    '      "name": "implements-Klausel unzulässig",',
    '      "description": "Eine Delegation mit implements verletzt eine ihrer festen Regeln: implements nur in Klassen (wie E2258), nur an Properties mit Klassen- oder Interface-Typ (wie E2259; gemeldet fü' +
    'r eingebaute Typen, Records und Aufzählungen), nicht zusammen mit index (wie E2260), nur an lesbaren Properties (wie E2261), der Getter ohne andere Aufrufkonvention als register (wie E2262) und nicht ' +
    'dynamic oder message (wie E2263; Delphi 13 meldet zusätzlich E2148), jedes Interface nur über eine Property (wie E2257) und keine Methodenzuordnung für ein so umgesetztes Interface (wie E2264). Typen ' +
    'werden über die uses-Klauseln aufgelöst; unbekannte Typen, Aliase und Properties in bedingten Zweigen bleiben still."',
    '    },',
    '{',
    '      "id": "declaration-invalid",',
    '      "name": "Deklaration, die der Compiler ablehnt",',
    '      "description": "Eine Deklaration, die Delphi schon wegen ihrer Form ablehnt: packed vor einem anderen Typ als array, record, object, class, set, file oder string (wie E2006), eine Routine mit Er' +
    'gebnistyp file (wie E2024), ein virtueller Konstruktor in einem object-Typ (wie E2062), eine Property ohne read, write und index in einem Interface, das kein dispinterface ist, oder in einem automated' +
    '-Abschnitt (wie E2128) oder zwei Konstruktoren mit verschiedenen Namen und denselben Parametertypen, wenn das Projekt C++-Ausgaben erzeugt (DCC_CBuilderOutput oder Schalter -J in der .dproj, wie W1029' +
    '). Neudeklarationen von Properties ohne Typ bleiben still. Keine Korrektur: Die richtige hängt von der Absicht ab."',
    '    },',
    '{',
    '      "id": "member-hides-ancestor",',
    '      "name": "Member verdeckt einen Member des Vorfahren",',
    '      "description": "Eine Property heißt wie ein Feld eines Vorfahren (wie W1009), ein Feld wie ein Feld oder eine Property eines Vorfahren oder eine nicht virtuelle Methode hat Namen und Parameter e' +
    'iner nicht virtuellen Methode eines Vorfahren (die beiden letzten ohne Code: Delphi 13 übersetzt sie still). Code, der über den Vorfahrtyp zugreift, sieht weiter den alten Member. Virtuelle Methoden m' +
    'eldet hides-virtual, lokale Namen shadowed-name. Neu veröffentlichte Properties (property Caption;), Properties mit neuem Typ über einer Property des Vorfahren, Methoden, die eine Methode eines Interf' +
    'aces aus der eigenen Vorfahrenliste umsetzen (QueryInterface über TInterfacedObject), overload, reintroduce, Konstruktoren und Klassenmethoden bleiben unbeanstandet. Member, die der Nachfahre nicht si' +
    'eht (private einer anderen Unit, strict private mit ignoreStrictPrivate), zählen nicht; Vorfahren kommen aus der Datei und dem Symbolindex. Korrektur für Felder und Properties: den Member in der Klass' +
    'endeklaration und in den Rümpfen ihrer Methoden in dieser Unit umbenennen (aus FName wird FKundeName).",',
    '      "options": [',
    '        {',
    '          "name": "ignoreStrictPrivate",',
    '          "description": "Verdeckte strict private Member des Vorfahren nicht melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "published-type-invalid",',
    '      "name": "Unzulässiges Mitglied im published-Abschnitt",',
    '      "description": "Ein Mitglied hinter einem ausdrücklichen published, das der Compiler ablehnt: eine Property vom Typ statisches Array, Zeiger oder Prozedurtyp ohne of object (wie E2188; Records u' +
    'nd dynamische Arrays übersetzt dcc), vom Typ Real48 (wie E2186) oder eine Menge über 4 Byte (wie E2187), ein Feld, das weder Klasse noch Interface ist (wie E2217), mehr als eine published-Überladung (' +
    'wie E2266), eine Klassen-Property (wie E2545) oder ein Name mit Zeichen außerhalb von ASCII (wie E2452). Typen löst die Regel über die Datei und den Index auf und verfolgt Aliase; Typparameter, unbeka' +
    'nnte Typen und Abschnitte, deren published in einem anderen Zweig der bedingten Übersetzung steht als das Mitglied, bleiben still. Den Abschnitt ohne Sichtbarkeitsangabe prüft sie nicht, weil der Comp' +
    'iler solche Mitglieder dort still zu public herabstuft. Korrektur: das Mitglied in den public-Abschnitt verschieben."',
    '    },',
    '{',
    '      "id": "override-case-mismatch",',
    '      "name": "Schreibweise oder Sichtbarkeit weicht vom Vorfahren ab",',
    '      "description": "Eine überschreibende Methode schreibt ihren Namen anders als der Vorfahr (destructor destroy, wie H2365) oder ist weniger sichtbar als die überschriebene Methode (wie H2269, nur ' +
    'für Klassen im interface-Teil; verglichen werden die Stufen privat, geschützt, öffentlich), ein Getter oder Setter heißt Get<Property> bzw. Set<Property>, ist aber anders geschrieben, oder eine inline' +
    '-Methode greift auf ein Mitglied zu, das weniger sichtbar ist als sie selbst (diese beiden ohne Code: Delphi 13 meldet dort weder H2367 noch H2440). Wichtig für C++Builder-Nutzer der Units und für ein' +
    'heitlichen Code. Die Docwiki führt H2269 und H2367 als X2269 und X2367, weil sich ihre Stufe umstellen lässt; dcc meldet sie standardmäßig als Hinweis. H2368 und H2369 deckt die Regel nicht ab, weil n' +
    'icht dokumentiert ist, wann dcc sie meldet. Standardmäßig aus; in atlas.json einschalten. Korrekturen: Schreibweise vom Vorfahr übernehmen, Zugriffsmethode umbenennen."',
    '    },',
    '{',
    '      "id": "default-property-invalid",',
    '      "name": "default-Property falsch deklariert oder fehlt",',
    '      "description": "default; hinter einer Property ohne Indexparameter (wie E2132), eine zweite default-Property derselben Klasse mit anderem Namen oder denselben Indextypen (wie E2131; Überladung ü' +
    'ber den Indextyp unter demselben Namen ist erlaubt) oder Obj[I] auf einer Klasse, die in ihrer ganzen Vorfahrenkette keine default-Property hat (wie E2149). Den Typ von Obj ermittelt die Namensauflösu' +
    'ng; nicht auflösbare Typen, abgebrochene Vorfahrenketten und Klassen mit einem Class-Helper in der Unit bleiben still. Neudeklarationen ohne Typ (property Items; default;) übernehmen den Index des Vor' +
    'fahren und werden nicht geprüft."',
    '    },',
    '{',
    '      "id": "property-redeclaration-invalid",',
    '      "name": "Neu deklarierte Property fehlt im Vorfahren",',
    '      "description": "Eine Neudeklaration ohne Typ wie property Caption; (um Sichtbarkeit oder Standardwert zu ändern) nennt eine Property, die kein Vorfahr hat (wie E2147), oder die Property des Vorf' +
    'ahren ist von hier aus nicht erreichbar: strict private oder private in einer anderen Unit (wie E2233). Gemeldet nur, wenn die ganze Vorfahrenkette bekannt ist; ein gleichnamiges Feld oder eine Method' +
    'e und Deklarationen in inaktiven Zweigen bleiben still. Korrektur: den ähnlichsten Property-Namen der Vorfahren verwenden."',
    '    },',
    '{',
    '      "id": "inline-not-expanded",',
    '      "name": "Inline-Funktion wird nicht eingebettet",',
    '      "description": "Aufruf einer inline-Routine aus einer anderen Unit, die der Compiler nicht einbettet: Ihr Rumpf braucht eine Unit, die hier in uses fehlt (wie H2443, typisch System.Generics.Coll' +
    'ections bei TJSONObject.Count), die aufrufende Routine ist selbst inline und die Unit der gerufenen steht nur im uses des implementation-Teils (wie H2445), oder die Unit der gerufenen Routine verwende' +
    't diese Unit direkt (wie H2456) bzw. über andere Units (wie H2457; nur, wenn der Rumpf auf mehr als eingebaute Typen, Intrinsics und System verweist). Geprüft werden Aufrufe, Properties mit inline-Get' +
    'ter bzw. -Setter (auch die default-Property hinter Liste[0]) und for-in (GetEnumerator, MoveNext, Current). Der Index merkt sich, worauf jeder inline-Rumpf verweist; die Regel meldet nur, was sie sich' +
    'er auflöst (unbekannte Verweise und geerbte Mitglieder aus anderen Units bleiben stumm; ein Alias einer Deklaration aus System wie tkRecord in System.TypInfo braucht dessen Unit nicht). Zugriffe auf p' +
    'rivate- oder strict private-Mitglieder meldet sie nicht: Delphi 13 bettet solche Aufrufe ein. Mit {$INLINE OFF} in der Datei schweigt sie. Korrektur: die fehlenden Units in das uses des Abschnitts auf' +
    'nehmen."',
    '    },',
    '{',
    '      "id": "compiler-hints",',
    '      "name": "Compilerhinweis ohne eigene Regel",',
    '      "description": "Hinweise und Warnungen des Compilers, die zu keiner anderen Regel gehören. published in einer Klasse ohne RTTI: Der Compiler schaltet für sie {$M+} ein (wie W1055); gemeldet einm' +
    'al je Klasse am ersten Mitglied hinter dem ersten ausdrücklichen published, still bei {$M+} oder {$TYPEINFO ON} an der Deklaration, bei einem Vorfahren mit RTTI (bekannte Nachfahren von TPersistent, {' +
    '$M+} an seiner Deklaration oder eigene published-Mitglieder) und nach {$WARN TYPEINFO_IMPLICITLY_ADDED OFF} oder {$WARNINGS OFF}; ein Vorfahr, dessen Kette nicht bis TObject bekannt ist oder dessen Da' +
    'tei sich nicht lesen lässt, hält die Regel still, ebenso generische und verschachtelte Klassen. Initialize oder Finalize mit einer Variablen eines eingebauten Typs ohne verwaltete Teile wie Integer, D' +
    'ouble oder Boolean, auch über Aliase (wie H2243), oder mit einer Variablen eines Zeigers auf einen verwalteten Typ wie PString oder PVariant, wo wohl P^ gemeint war (wie H2244); nur Aufrufe mit einem ' +
    'einfachen Bezeichner, dessen Typ sicher bekannt ist, still nach {$HINTS OFF} und wenn Initialize bzw. Finalize eine eigene Routine oder ein Mitglied meinen kann (with, Methode einer Klasse mit unbekan' +
    'ntem Vorfahren)."',
    '    },',
    '{',
    '      "id": "constant-expression-error",',
    '      "name": "Fehler in einem konstanten Ausdruck",',
    '      "description": "Ein konstanter Ausdruck teilt durch null (wie E2098) oder läuft über (wie E2099: über Int64 hinaus, wenn alle Operanden ein Vorzeichen haben, etwa High(Int64) + 1, sonst über UIn' +
    't64 hinaus), ein Bereich hat die Untergrenze über der Obergrenze (array[5..1], wie E2011), eine Konstante verletzt einen ganzzahligen Typ fester Größe oder einen Teilbereichstyp (wie E1012; Werte, die' +
    ' nur als gleich breite Zahl mit anderem Vorzeichen passen, etwa $FFFFFFFF für Integer oder -1 für Cardinal, wie W1012 als Warnung; bei Zuweisungen nur Werte außerhalb von 0..127), ein konstanter Index' +
    ' liegt außerhalb eines statischen Arrays der Datei oder eine einzelne case-Marke außerhalb des Ganzzahltyps des case-Ausdrucks (wie E1012), ein Hex-, Binär- oder Oktalliteral braucht mehr als 64 Bit (' +
    'wie E2102; an Int64 zugewiesen zusätzlich wie W1012), eine Menge hat mehr als 256 Elemente (set of 0..300, set of Word, wie E2028) oder eine Sichtbarkeitsmenge in {$RTTI} enthält Zahlen oder Strings s' +
    'tatt vcPrivate, vcProtected, vcPublic und vcPublished (wie E2572). Atlas wertet Literale, Konstanten (auch aus anderen Units) und SizeOf/High/Low von Typen fester Größe aus; eine Konstante aus einem {' +
    '$IF}-Zweig zählt nur, wo die geprüfte Stelle mit ihr zusammen übersetzt wird. Ausdrücke mit unbekannten Teilen bleiben still."',
    '    },',
    '{',
    '      "id": "typed-constant-modified",',
    '      "name": "Typisierte Konstante verändert",',
    '      "description": "Einer typisierten Konstante (const Zaehler: Integer = 0) wird etwas zugewiesen (wie W1017, auch einem Element oder Record-Feld davon), oder sie wird als var- oder out-Argument üb' +
    'ergeben, auch an Inc, Dec, Include, Exclude, Delete, SetLength und ähnliche (wie W1016). Gemeint war meist eine Variable; übersetzbar ist das nur mit {$J+}, und gilt {$J+} vor der Deklaration, schweig' +
    't die Regel wie dcc. Gilt vor der Deklaration in derselben Datei oder in einer davor eingebundenen Include-Datei {$J-} bzw. {$WRITEABLECONST OFF}, meldet Atlas einen Fehler (wie E2064 bzw. E2197). Daz' +
    'u 0 als Wert einer Zeigerkonstante oder einer initialisierten Zeigervariable (wie W1013). Korrekturen: eine Konstante auf Unit-Ebene in eine Variable mit Initialwert umwandeln (der const-Abschnitt wir' +
    'd bei Bedarf geteilt; lokale typisierte Konstanten behalten ihren Wert zwischen Aufrufen und bekommen keine Korrektur); nil statt 0 schreiben."',
    '    },',
    '{',
    '      "id": "string-length-limit",',
    '      "name": "String-Grenze überschritten",',
    '      "description": "Ein String-Literal wird an ein Ziel vom Typ string[N] oder ShortString gekürzt: Zuweisung, typisierte Konstante oder initialisierte Variable, auch über eigene Aliase, string[Kons' +
    'tante] und Felder aus anderen Units (wie W1014). Vor Delphi 12 (delphiVersion unter 23) darf ein Literal in Anführungszeichen höchstens 255 Zeichen haben (wie E2056), und ein resourcestring höchstens ' +
    '4096 Zeichen, mit + verbundene Literale eingerechnet (wie E2381); beides sind Fehler. Gezählt wird wie geschrieben, '''' und #13 zählen als ein Zeichen. Korrekturen: das Ziel als string deklarieren (ein' +
    'zelne Variable oder typisierte Konstante derselben Datei; Record-Felder behalten ihre Größe); das Literal in Stücke zu 255 Zeichen teilen, verbunden mit +."',
    '    },',
    '{',
    '      "id": "dynamic-array-misuse",',
    '      "name": "New, Dispose oder SetLength falsch für dynamische Arrays",',
    '      "description": "New (wie E2255) oder Dispose (wie E2008 in Delphi 13, dokumentiert als E2256) auf einem dynamischen Array, SetLength ohne Länge (wie E2246), New mit Länge auf einem Typ, der kein' +
    ' dynamisches Array ist (wie E2008 in Delphi 13, dokumentiert als E2307), und New(TArrayTyp) ohne Länge (wie E2308). Häufig in altem Code, der von Zeigern auf dynamische Arrays umgestellt wurde. Die Re' +
    'gel meldet nur, wenn die Namensauflösung Variable bzw. Typ sicher kennt; Aliase werden verfolgt (TWerte = array of Double), TBytes und die übrigen dynamischen Arrays der RTL gelten auch ohne Index; of' +
    'fene Array-Parameter und Zeiger bleiben still. Korrekturen: Dispose(A) wird A := nil, New(A) wird SetLength(A, 1)."',
    '    },',
    '{',
    '      "id": "local-routine-as-callback",',
    '      "name": "Lokale Routine als Prozedurvariable",',
    '      "description": "Eine lokale (verschachtelte) Routine wird einer Variablen oder einem Parameter eines prozeduralen Typs ohne of object zugewiesen (wie E2094), oder eine typisierte Konstante einer' +
    ' Routine nimmt die Adresse einer lokalen Variablen (wie E2278). Gemeint ist meist eine anonyme Methode oder eine Routine der Unit. Die Regel meldet nur, wenn die Namensauflösung den Zieltyp sicher ken' +
    'nt; Methodenzeiger und Methodenreferenzen bleiben still, weil der Compiler sie mit anderen Codes meldet, ebenso @Routine (ein untypisierter Zeiger). Korrektur: die Routine als Routine der Unit vor die' +
    ' umgebende Routine verschieben, wenn sie nichts aus ihr nutzt (keine lokalen Namen weiter außen, keine Klassenmitglieder ohne Präfix)."',
    '    },',
    '{',
    '      "id": "hresult-integer-mix",',
    '      "name": "Integer und HRESULT vertauscht",',
    '      "description": "Eine Klasse implementiert eine Interface-Methode mit HRESULT-Ergebnis über eine Methode mit Integer- (bzw. LongInt-) Ergebnis oder umgekehrt (wie W1008; die Delphi-Hilfe nennt X1' +
    '008). Beide sind 32 Bit groß, deshalb fällt es nicht auf; die Bedeutung der Werte (S_FALSE als Erfolg) geht aber verloren; wichtig für COM- und OTA-Code. Zugeordnet wird über Name und Parametertypen s' +
    'amt Zuordnungen wie function IFoo.Bar = Baz; Interfaces samt ihren Vorfahren kommen aus der Datei bzw. dem Index. Stehen Varianten in bedingten Zweigen, meldet die Regel nur, wenn jede Variante abweic' +
    'ht. Korrektur: den Ergebnistyp in Deklaration und Implementierung an das Interface angleichen."',
    '    },',
    '{',
    '      "id": "inherited-abstract-call",',
    '      "name": "inherited ruft eine abstrakte Methode auf",',
    '      "description": "inherited mit ausdrücklichem Methodennamen, etwa inherited Zeichnen(C), obwohl die Methode im Vorfahren abstract ist: Der Aufruf löst zur Laufzeit EAbstractError aus. Der Compile' +
    'r übersetzt ihn ohne Fehler. Ein bloßes inherited; übergeht der Compiler bei abstrakten Methoden still; das meldet die Regel nicht. Die Methode löst die Namensauflösung samt Überladungen auf; gemeldet' +
    ' wird nur, wenn jede passende Überladung abstrakt ist. Korrektur: den Aufruf entfernen, wenn er als eigene Anweisung in einem begin…end steht."',
    '    },',
    '{',
    '      "id": "generic-constraint-violated",',
    '      "name": "Typargument verletzt eine Einschränkung",',
    '      "description": "Ein Typargument erfüllt die Einschränkung seines Typparameters nicht: class (wie E2511), record (wie E2512), constructor (wie E2513), ein Interface (wie E2514) oder eine Basiskla' +
    'sse (wie E2515). In Methoden eines generischen Typs dieser Datei meldet die Regel außerdem T.Create ohne constructor-Einschränkung (wie E2568) und Methodenaufrufe auf Werten eines Typparameters ganz o' +
    'hne Einschränkung (wie E2571). Den generischen Typ löst die Namensauflösung samt Zahl der Typparameter auf, seine Einschränkungen stammen aus seiner Deklaration in der Datei oder im Symbolindex. Argum' +
    'ente, die selbst Typparameter sind, Aliase und Typen mit unvollständiger Vorfahrenkette meldet die Regel nicht. Korrektur für einen Typparameter dieser Datei, der allein in seiner Gruppe steht: die Ei' +
    'nschränkung ergänzen (T: class, constructor bzw. T: class)."',
    '    },',
    '{',
    '      "id": "unresolved-type",',
    '      "name": "Typ in einer Deklaration nicht gefunden",',
    '      "description": "Ein Typname in einer Deklaration (Feld, Parameter, Ergebnis, Vorfahr, Interface-Liste, Variable, Typargument) ist nicht deklariert (wie E2003, beim Ziel eines Zeigertyps wie E256' +
    '4) oder kein Typ: eine Variable oder ein Mitglied hinter einem Punkt wie E2005, eine Routine wie E2007, eine Konstante wie E2029 (Delphi liest sie als Anfang eines Teilbereichs und erwartet ''..''). Typ' +
    'en, die der Compiler ohne Deklaration in System.pas kennt (Text, TextFile, Real48, OpenString …), gelten als deklariert. Ergänzt unresolved-identifier, das nur Anweisungen prüft. Dieselben Vorbedingun' +
    'gen wie bei unresolved-attribute: System im Symbolindex, alle Units aus uses bekannt, nicht in {$IF…}-Blöcken. Typparameter, Namen, die die Datei irgendwo als Typ deklariert (auch verschachtelt), und ' +
    'Namen, die der Index als verschachtelten Typ kennt (geerbte innere Typen), meldet die Regel nicht. Korrektur: die Unit, die den Typ (mit gleich vielen Typparametern) deklariert, in uses aufnehmen."',
    '    },',
    '{',
    '      "id": "class-reference-nonvirtual-constructor",',
    '      "name": "Konstruktor über Klassenreferenz nicht virtuell",',
    '      "description": "Create über eine Klassenreferenz (class of TBasis), deren Konstruktor nicht virtual ist. Unter Win32 und Win64 übersetzt das ohne Meldung, erzeugt aber immer über den Konstruktor' +
    ' von TBasis: Felder, die Nachfahren in ihren eigenen Konstruktoren setzen, bleiben leer (wie E2391). Der Empfänger kann eine Variable, ein Feld, ein Parameter oder ein Funktionsergebnis vom Typ einer ' +
    'Klassenreferenz sein; den Konstruktor löst die Namensauflösung in der nächsten Klasse auf, die ihn deklariert, Überladungen nach Zahl der Argumente. Still, wenn eine passende Überladung virtual, dynam' +
    'ic, override oder abstract ist, wenn eine Deklaration in einem anderen Zweig der bedingten Übersetzung steht und wenn ein Typ nicht auflösbar ist. Korrektur, wenn der Konstruktor in dieser Datei steht' +
    ': virtual an ihn und override an die gleichlautenden Konstruktoren der Nachfahren in dieser Datei."',
    '    }');

implementation

end.
