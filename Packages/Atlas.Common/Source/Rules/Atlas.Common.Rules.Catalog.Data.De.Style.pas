unit Atlas.Common.Rules.Catalog.Data.De.Style;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeStyle: array[0..553] of string = (
    '{',
    '      "id": "unused-local",',
    '      "name": "Ungenutzte lokale Variable",',
    '      "description": "Eine lokale Variable ist deklariert, wird aber nie verwendet. Wie Compilerhinweis H2164, aber schon beim Tippen.",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unused-parameter",',
    '      "name": "Ungenutzter Parameter",',
    '      "description": "Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen' +
    ' und Callbacks, auch Routinen in Tabellen von Routinen (typisierte Konstanten, Array-Literale). Eine Routine, die nur aus einer anonymen Methode aufgerufen wird, hat eine freie Signatur und wird gemel' +
    'det. Die Übergabe als Wert in einer anderen Unit sieht die Regel nicht; dort mit lsp-ignore und Grund unterdrücken.",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unused-assignment",',
    '      "name": "Zugewiesener Wert ungenutzt",',
    '      "description": "Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077, den dcc nur für nicht verwaltete Typen g' +
    'ibt: Bei Strings, dynamischen Arrays, Variants und Records mit solchen Feldern sowie bei Variablen ohne Typangabe nennt die Meldung keinen Code (#1383). Variablen mit Interface-Typ sind ausgenommen: D' +
    'ie Zuweisung hält oder gibt eine Referenz frei (Bereichswächter, Writer := nil). Ebenso still bleibt das Leeren eines zuvor gesetzten Werts (X := nil, '''', Default(T), T.Empty): Es gibt Speicher und Re' +
    'ferenzen vorzeitig frei oder schützt nach Free. Leeren ohne vorherigen Wert wird weiter gemeldet. Auch Result zählt, wenn die Funktion einen nicht verwalteten Ergebnistyp hat (Integer, Boolean, Aufzäh' +
    'lungen, Klassen): Eine Vorbelegung wie Result := False vor try/except, case oder einer Schleife, nach der jeder Weg Result neu setzt oder mit Exit(Wert) endet, wird gemeldet (#1345). Gelesen wird Resu' +
    'lt am normalen Ende der Routine, nicht beim Verlassen über eine Ausnahme.",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "file-header",',
    '      "name": "Dateikopf fehlt oder weicht ab",',
    '      "description": "Die Datei beginnt nicht mit dem Kopf aus der Regeloption \"template\". Standardmäßig aus; in atlas.json mit einer Vorlage einschalten. Die Schnellkorrektur fügt den Kopf ein.",',
    '      "options": [',
    '        {',
    '          "name": "template",',
    '          "description": "Erwarteter Dateikopf; Platzhalter wie dokumentiert."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "hardcoded-string",',
    '      "name": "Text im Code statt resourcestring",',
    '      "description": "In einer Anweisung steht ein String mit Wörtern für Menschen. In einen resourcestring auslagern, damit er übersetzt werden kann. Still bei Texten, die niemand übersetzt: Argument' +
    'e von Protokoll- und Prüfaufrufen (…Log, Log…, Diagnose, Trace, Debug, Assert, OutputDebugString), Vergleichs- und Registry-Aufrufen (StartsText, Pos, ReadString …), Masken von FormatDateTime und Form' +
    'atFloat, Markup (HTML ab <, JSON ab { oder \"Schlüssel\":, Markdown-Überschriften # und ##) und Font.Name; die Option ignoreCalls nennt weitere Routinen. Standardmäßig aus, niedrige Konfidenz."',
    '    },',
    '{',
    '      "id": "bool-compare",',
    '      "name": "Vergleich mit True oder False",',
    '      "description": "Ein Vergleich eines Boolean mit True oder False ist überflüssig; den Ausdruck oder not direkt verwenden."',
    '    },',
    '{',
    '      "id": "redundant-assigned-free",',
    '      "name": "Assigned-Prüfung vor Free",',
    '      "description": "Free prüft selbst auf nil, eine Assigned-Prüfung vor Free oder FreeAndNil ist überflüssig."',
    '    },',
    '{',
    '      "id": "redundant-parens",',
    '      "name": "Überflüssige Klammern",',
    '      "description": "Klammern um eine ganze Bedingung oder einen einzelnen Bezeichner bringen nichts. Standardmäßig aus."',
    '    },',
    '{',
    '      "id": "redundant-cast",',
    '      "name": "Überflüssige Typumwandlung",',
    '      "description": "TStringList(Liste) mit Liste: TStringList, X as TFoo mit X: TFoo oder Integer(Anzahl) mit Anzahl: Integer ändern nichts. Ebenso TObject(Obj).Free: Free ruft den virtuellen Destru' +
    'ktor und braucht keine Umwandlung (Option checkFree). Gemeldet wird nur, wenn der Typ der Quelle sicher bekannt und genau mit dem Namen des Ziels deklariert ist; Aliase (TFarbIndex = Integer), Konstan' +
    'ten, Routinen ohne Aufruf, überladene Routinen als Quelle, Argumente überladener Aufrufe (die Umwandlung kann die Überladung wählen), as mit Interfaces (QueryInterface) und in der Klassenkette neu dek' +
    'lariertes Free bleiben still. Sicherheit hoch. Korrektur: die Umwandlung entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "checkFree",',
    '          "description": "Auch eine Klassenumwandlung melden, die nur vor Free steht (CastAndFree)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "redundant-begin-end",',
    '      "name": "begin … end um eine einzelne Anweisung",',
    '      "description": "Ein begin … end-Block mit genau einer Anweisung kann entfallen. Standardmäßig aus."',
    '    },',
    '{',
    '      "id": "with-statement",',
    '      "name": "with-Anweisung",',
    '      "description": "In einem with-Block ist unklar, zu welchem Objekt ein Bezeichner gehört, und ein neues Mitglied des with-Objekts ändert still die Bedeutung. Den Ausdruck ausschreiben oder eine l' +
    'okale Variable verwenden."',
    '    },',
    '{',
    '      "id": "metric-method-length",',
    '      "name": "Methode zu lang",',
    '      "description": "Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteile' +
    'n. Den Grenzwert setzt die Option max, z. B. \"rules\": {\"metric-method-length\": {\"max\": 80}}.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Anweisungszeilen."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-nesting-depth",',
    '      "name": "Zu tief verschachtelt",',
    '      "description": "Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder inn' +
    'ere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchste erlaubte Schachtelungstiefe."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-cyclomatic-complexity",',
    '      "name": "Zyklomatische Komplexität zu hoch",',
    '      "description": "Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/o' +
    'r in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchste erlaubte zyklomatische Komplexität."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-cognitive-complexity",',
    '      "name": "Kognitive Komplexität zu hoch",',
    '      "description": "Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else' +
    ', else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchste erlaubte kognitive Komplexität."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-parameter-count",',
    '      "name": "Zu viele Parameter",',
    '      "description": "Die Methode hat mehr Parameter als der Grenzwert (Vorgabe 6). Zusammengehörige Werte in einem Record oder einer Klasse bündeln. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Parameter."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-boolean-operands",',
    '      "name": "Bedingung mit zu vielen Operanden",',
    '      "description": "Eine Bedingung von if, while, until oder einem Bedingungsausdruck verknüpft mehr Operanden mit and, or und xor als der Grenzwert (Vorgabe 5); Klammern und not zählen nicht, ein V' +
    'ergleich oder Aufruf ist ein Operand. Der Befund steht auf der Bedingung. Schnellkorrektur „Bedingung in Funktion auslagern“ (#50) macht aus der ganzen Bedingung eine Funktion mit Ergebnis Boolean (Me' +
    'thode der Klasse bzw. Routine vor der umgebenden), die gelesenen lokalen Namen werden const-Parameter. Erscheint auch in der Metrik-Linse.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Operanden in einer Bedingung."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-local-count",',
    '      "name": "Zu viele lokale Variablen",',
    '      "description": "Die Routine deklariert mehr lokale Variablen als der Grenzwert (Vorgabe 12): Namen im var-Abschnitt, Inline-Variablen und for var. Lokale Routinen und anonyme Methoden zählen für' +
    ' sich. Viele lokale Variablen heißen meist, dass die Routine mehreres tut; Teile in eigene Methoden auslagern. Erscheint auch in der Metrik-Linse.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele lokale Variablen."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-exit-points",',
    '      "name": "Zu viele Ausstiege",',
    '      "description": "Die Routine wird öfter mit Exit und raise verlassen als der Grenzwert (Vorgabe 4); Exit(Wert) und raise; im except zählen mit. Lokale Routinen und anonyme Methoden zählen für sic' +
    'h. Viele Ausstiege machen den Ablauf schwer lesbar; Wächter zusammenfassen oder Teile auslagern. Erscheint auch in der Metrik-Linse.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Exit und raise."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "todo-comment",',
    '      "name": "Offener TODO-Kommentar",',
    '      "description": "Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Pr' +
    'iorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Er' +
    'ledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe [\"TODO\", \"FIXME\"]); sie gilt auch für get_todos und --todos.",',
    '      "options": [',
    '        {',
    '          "name": "keywords",',
    '          "description": "Marken offener TODO-Einträge (nur Buchstaben)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unneeded-forward-declaration",',
    '      "name": "Überflüssige Forward-Deklaration",',
    '      "description": "Eine Forward-Deklaration, deren Typ im selben type-Block vor der vollständigen Deklaration nicht benutzt wird. Schnellkorrektur: entfernen."',
    '    },',
    '{',
    '      "id": "shadowed-name",',
    '      "name": "Lokaler Name verdeckt Feld oder Property",',
    '      "description": "Ein Parameter, eine lokale oder Inline-Variable heißt wie ein Feld oder eine Property der Klasse (auch geerbt und dort sichtbar, aufgelöst über die Datei und den Symbolindex) ode' +
    'r wie eine globale Variable der Unit, die vor der Routine deklariert ist. In Formularmethoden besonders tückisch: Caption, Name, Tag, Left. Steht die VCL nicht im Index, kennt die Regel die Mitglieder' +
    ' von TComponent und TControl, wenn die Vorfahrenkette an einer VCL-Grundklasse endet. Mitglieder, die aus RTL, VCL oder einer anderen Bibliothek geerbt sind (Unit aus dem Bibliothekspfad), meldet die ' +
    'Regel nur, wo sie gemeint sein könnten: eine lokale Variable, die nur zugewiesen oder nur gelesen wird, ein Werteparameter, dem etwas zugewiesen wird. Hilfsvariablen wie Left, Text oder Name, die gele' +
    'sen und geschrieben werden, bleiben still; die Option frameworkMembers meldet sie wie früher. Parameter von Ereignis-Handlern (mit Sender) und von Methoden mit override oder message bleiben außen vor,' +
    ' weil der Ereignistyp, der Vorfahr bzw. die Botschaft die Signatur vorgibt. Konfidenz hoch. Schnellkorrektur: in der Routine in AName (Parameter, auch in der Deklaration) bzw. LName (lokale Variable) ' +
    'umbenennen; setzt die Projektdatei .atlas Präfixe (naming), gelten diese, z. B. mName. Die Option ignore nennt Namensmuster, die nie gemeldet werden (Vorgabe Sender, Value).",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster (* und ?), die nie gemeldet werden."',
    '        },',
    '        {',
    '          "name": "frameworkMembers",',
    '          "description": "Jeden lokalen Namen melden, der ein aus RTL, VCL oder einer Bibliothek geerbtes Mitglied verdeckt, nicht nur verdächtige."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "naming-prefix",',
    '      "name": "Name ohne das Präfix seiner Art",',
    '      "description": "Einer lokalen Variable (auch Inline und for var), einem Feld (auch class var), einem Parameter oder einer Konstante (const, auch lokal, in Klassen und Inline; nicht resourcestrin' +
    'g) fehlt das Präfix ihrer Art. Standard: lokal m, Feld F, Parameter A, Konstante c; hinter einem Präfix, das auf einen Buchstaben endet, folgt ein Großbuchstabe oder eine Ziffer (mIndex, nicht menu). ' +
    'Globale Variablen prüft die Regel nicht. Je Art kommt das Präfix aus der Option in atlas.json, sonst aus der Projektdatei .atlas (naming, auch constant), sonst der Standard; ein leerer Wert schaltet d' +
    'ie Art ab. Standardmäßig aus: Die Regel läuft nur, wenn atlas.json sie einschaltet. Ausnahmen: Schleifenzähler aus einem Buchstaben, Sender, Self und Result, Namen nach ignore, öffentliche Felder (pub' +
    'lic, published und Felder eines Records vor seinem ersten Sichtbarkeitsabschnitt: Das F gilt nur für Felder hinter Properties, nicht für TPoint.X), Felder vor dem ersten Sichtbarkeitsabschnitt eines F' +
    'ormulars, Frames oder Datenmoduls (Komponenten), Parameter von Methoden mit override oder message, von published-Methoden, von Ereignis-Handlern (ein Parameter heißt Sender) und von Methoden, die eine' +
    ' Interface-Methode erfüllen (in der Datei oder im Symbolindex; unbekanntes Interface: still). Parameter werden nur an der Deklaration gemeldet. Schnellkorrektur: in den erwarteten Namen umbenennen, in' +
    ' der Routine bzw. im Block ab einer Inline-Deklaration, bei Parametern auch in Deklaration und Implementierung, bei privaten Feldern und Klassenkonstanten in der Klasse und ihren Methoden (auch Self.N' +
    'ame und TTyp.Name), bei Konstanten der implementation in der ganzen Unit. Keine Korrektur, wenn der neue Name dort schon vorkommt, wo umbenannt wird (Routine samt Parameterliste, bei Feldern die Klass' +
    'e und ihre Methoden, bei Konstanten der implementation die Datei), der Bereich with enthält, eine verschachtelte Routine den Namen neu deklariert oder der Name außerhalb der Datei sichtbar ist. Läuft ' +
    'die Regel, bilden andere Korrekturen und Refactorings neue Namen mit diesen Präfixen (Konstante einführen → cNewConstant, Variable einführen und with auflösen → mValue, Parameter von „Methode anlegen“' +
    ' → APreis), damit die Regel sie nicht gleich wieder meldet.",',
    '      "options": [',
    '        {',
    '          "name": "local",',
    '          "description": "Präfix lokaler Variablen; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "field",',
    '          "description": "Präfix von Feldern; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "parameter",',
    '          "description": "Präfix von Parametern; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "constant",',
    '          "description": "Präfix von Konstanten; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster (* und ?), die nie gemeldet werden, z. B. Felder von API-Records."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "boolean-assign-if",',
    '      "name": "if, das nur True oder False zuweist",',
    '      "description": "if B then X := True else X := False (auch mit begin/end und vertauschten Werten), if B then Exit(True) else Exit(False) sowie if B then Exit(True); gefolgt von Exit(False); lasse' +
    'n sich direkt schreiben. Ergänzt bool-compare. Konfidenz hoch. Schnellkorrektur: X := B, X := not B bzw. Exit(B); Verneinungen werden vereinfacht (aus not B wird B), zusammengesetzte Bedingungen einge' +
    'klammert. Ohne Korrektur, wenn Kommentare im if stehen."',
    '    },',
    '{',
    '      "id": "magic-number",',
    '      "name": "Zahl ohne Namen im Code",',
    '      "description": "Zahlenliterale (dezimal, $hex, Gleitkomma, mit Vorzeichen) in Anweisungen, außerhalb von const-Abschnitten, Typen, Array-Grenzen und Teilbereichen. Still bei Zahlen, die für sich' +
    ' sprechen: DPI-Basis 96 in MulDiv, volle Bitmasken ($FF, $FFFF, $FFFFFFFF), Zeiteinheiten 24, 60, 1000 und 3600 in *, /, div und mod sowie Argumente von Aufrufen in einem Array-Literal, deren Argument' +
    'e alle Zahlen sind (Punktlisten wie [P(3.5, 1.5), P(9.5, 1.5)]); SetBounds(12, 9, 360, 23) bleibt gemeldet. Erlaubte Werte sind einstellbar; DFM-Koordinaten und Tests lassen sich über exclude ausnehme' +
    'n. Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingeschaltet und minConfidence low ist. Schnellkorrektur: Konstante einführen (#50) im const-Abschnitt der Routine.",',
    '      "options": [',
    '        {',
    '          "name": "allowed",',
    '          "description": "Zahlen, die nie gemeldet werden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "line-length",',
    '      "name": "Zeile zu lang",',
    '      "description": "Zeilen über der Grenze max (Vorgabe 120 Zeichen, passend zu den Linealen aus #710). Tabs zählen bis zur nächsten Tabstelle nach format.indentSize. Zeilen, die nur wegen eines Str' +
    'ings oder, mit ignoreComments, eines Kommentars zu lang sind, werden nicht gemeldet. Zeilen über 1023 Zeichen meldet die Regel unabhängig von max immer als Warnung, weil der Compiler dort je nach Delp' +
    'hi-Version abbricht; Zeilen über 4095 Zeichen als Fehler, weil auch Delphi 13 dort abbricht (F2069). Standard aus. Schnellkorrektur: Zeile umbrechen hinter Kommas bzw. vor zweistelligen Operatoren, we' +
    'nn die Stücke danach passen.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstlänge einer Zeile in Zeichen."',
    '        },',
    '        {',
    '          "name": "ignoreStrings",',
    '          "description": "Zeilen, die nur wegen eines Strings zu lang sind, nicht melden."',
    '        },',
    '        {',
    '          "name": "ignoreComments",',
    '          "description": "Zeilen, die nur wegen eines Kommentars zu lang sind, nicht melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-class-size",',
    '      "name": "Klasse mit zu vielen Membern",',
    '      "description": "Die Klasse hat mehr Member als der Grenzwert (Vorgabe 40): Feldnamen, Methoden, Properties mit eigenem Typ und class var. Properties, die nur die Sichtbarkeit anheben (property A' +
    'lign;), und geschachtelte Typen zählen nicht; eine geschachtelte Klasse wird für sich gemessen. Erscheint auch in der Metrik-Linse über der Klasse. Die Klasse aufteilen oder Teile in Hilfsklassen ausl' +
    'agern; „Klasse in eigene Unit verschieben“ (#103) hilft, wenn auch die Unit voll ist.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstzahl der Member je Klasse."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-unit-length",',
    '      "name": "Unit zu lang",',
    '      "description": "Die Unit hat mehr Zeilen als der Grenzwert (Vorgabe 2000), gezählt bis zum abschließenden end. Gemessen werden nur Units, keine Programme oder Packages. Erscheint auch in der Met' +
    'rik-Linse über dem Unit-Namen. Klassen mit „Klasse in eigene Unit verschieben“ (#103) auslagern.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstzahl der Zeilen je Unit."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-uses-count",',
    '      "name": "Zu viele Units im uses",',
    '      "description": "Die Unit bindet mehr Units ein als der Grenzwert (Vorgabe 30), interface und implementation zusammen. Der Befund steht auf dem ersten uses. Programme und Bibliotheken werden nich' +
    't geprüft, weil ihr uses die Units des Projekts aufzählt. Erscheint auch in der Metrik-Linse über uses. Viele Abhängigkeiten heißen meist, dass die Unit zu viel tut; „Klasse in eigene Unit verschieben' +
    '“ (#103) teilt sie.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstzahl der Units in allen uses-Klauseln."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "metric-inheritance-depth",',
    '      "name": "Zu tiefe Vererbung",',
    '      "description": "Die Klasse hat mehr eigene Vorfahren als der Grenzwert (Vorgabe 5). Vorfahren aus RTL, VCL, FMX und anderen Bibliotheken zählen nicht (am Unit-Namen oder weil der Index sie aus d' +
    'em Bibliothekspfad nachgeladen hat), TObject ebenso. Vorfahren werden in der Datei und im Symbolindex gesucht. Bricht die Kette an einem unbekannten Vorfahren ab, bevor sie eine Bibliothek erreicht, i' +
    'st der Wert eine Untergrenze und die Meldung sagt „mindestens“; gemeldet wird nur, wenn schon sie über der Grenze liegt. Units einer Bibliothek selbst werden nicht geprüft. Der Befund steht auf dem Kl' +
    'assennamen; die Metrik-Linse zeigt die Tiefe neben den Membern.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele eigene Vorfahren."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "public-field",',
    '      "name": "Öffentliches Feld",',
    '      "description": "Felder im public- oder published-Abschnitt einer Klasse. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren oder mit TObject, weil der Formulardesigner dor' +
    't seine Felder anlegt. Records sind ausgenommen, außer mit includeRecords; class var und Hilfsklassen unter einem private- oder protected-type-Abschnitt werden nicht gemeldet. Standard aus. Schnellkor' +
    'rektur: Feld kapseln legt das Feld als FName in einen private-Abschnitt am Ende der Klasse und ergänzt im alten Abschnitt property Name read FName write FName; Zugriffe von außen bleiben gültig.",',
    '      "options": [',
    '        {',
    '          "name": "includeRecords",',
    '          "description": "Auch Felder von Records melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "legacy-tlist",',
    '      "name": "Ungenerische Liste mit Cast",',
    '      "description": "Eine ungenerische TList (System.Classes) oder TObjectList (System.Contnrs), deren Elemente mit Cast gelesen werden: T(Liste[I]), T(Liste.Items[I]), T(Liste.First), Liste[I] as T ' +
    'usw. TList<T> und TObjectList<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Die Regel meldet je Liste einmal, an ihrer Deklaration, wenn sie in der Datei ' +
    'steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Listentyp und Zieltyp sicher findet; Casts auf Pointer zählen nicht. Standard aus; für Code, der noch m' +
    'it alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur (#1105): wandelt die Liste in einem Schritt in TList<T> bzw. TObjectList<T> um: Deklaration, jedes Create (Argumen' +
    'te bleiben), jeden Cast und System.Generics.Collections im uses; Contnrs entfällt, wenn nichts anderes es braucht. Nur wenn alle Lesezugriffe denselben Cast haben, kein Mitglied ohne generisches Gegen' +
    'stück vorkommt (Sort mit TListSortCompare, Assign mit TListAssignOp, List), keine Pointer- oder Integer-Werte in der Liste stehen, Add, Extract, Remove und IndexOf T bekommen und die Liste nicht weite' +
    'rgegeben wird. Ist die Liste außerhalb der Unit sichtbar, schreibt die Korrektur die anderen Units der Projektgruppe mit um oder entfällt; solche Korrekturen wendet „Alle korrigieren“ (source.fixAll) ' +
    'nie an. Sonst nennt der Befund-Hover den Grund. Stapel und Warteschlangen: legacy-stack-queue."',
    '    },',
    '{',
    '      "id": "legacy-stack-queue",',
    '      "name": "Ungenerischer Stapel oder ungenerische Warteschlange mit Cast",',
    '      "description": "Ein ungenerischer TStack, TQueue, TObjectStack oder TObjectQueue (System.Contnrs), dessen Elemente mit Cast gelesen werden: T(Stapel.Pop), T(Stapel.Peek), Schlange.Pop as T usw. ' +
    'TStack<T>, TQueue<T>, TObjectStack<T> und TObjectQueue<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Wie legacy-tlist meldet die Regel je Stapel bzw. Wart' +
    'eschlange einmal, an der Deklaration, wenn sie in der Datei steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Typ und Zieltyp sicher findet; Casts auf Po' +
    'inter zählen nicht. Standard aus; für Code, der noch mit alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur: wandelt in einem Schritt um wie legacy-tlist; bei Warteschl' +
    'angen wird Push zu Enqueue und Pop zu Dequeue. TObjectStack<T> und TObjectQueue<T> besitzen ihre Objekte, die Contnrs-Klassen nicht: Die Korrektur erzeugt sie deshalb mit Create(False) und liest mit E' +
    'xtract, weil Pop und Dequeue dort Prozeduren sind, die das Objekt freigeben. Ohne Create in der Unit, mit verschiedenen Casts oder mit Mitgliedern ohne generisches Gegenstück (AtLeast) gibt es keine K' +
    'orrektur; der Befund-Hover nennt den Grund."',
    '    },',
    '{',
    '      "id": "global-variable",',
    '      "name": "Globale Variable im interface",',
    '      "description": "var oder threadvar im interface-Teil einer Unit: Jede Unit, die sie einbindet, kann den Wert lesen und ändern. Die Formularvariable des Designers (frmHaupt: TfrmHaupt, bei Nachfa' +
    'hren von TForm, TFrame, TDataModule oder jeder Klasse einer Unit mit Formulardatei) ist ausgenommen, außer mit includeFormVariables. Standard aus. Die Variable in den implementation-Teil verschieben u' +
    'nd eine Funktion oder Property anbieten.",',
    '      "options": [',
    '        {',
    '          "name": "includeFormVariables",',
    '          "description": "Auch die Formularvariablen des Designers melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "commented-out-code",',
    '      "name": "Auskommentierter Code",',
    '      "description": "Mindestens minLines aufeinanderfolgende Kommentarzeilen (// je Zeile oder ein mehrzeiliger { }-Kommentar), die sich als Anweisungen, Deklarationen oder Klassenmitglieder parsen l' +
    'assen. Prosa am Anfang und Ende des Blocks bleibt außen vor, mindestens die Hälfte der Zeilen muss nach Code aussehen (;, :=, begin, end, then, do). XMLDoc (///) und Kommentare vor dem ersten Token (L' +
    'izenzköpfe) meldet die Regel nie. Sicherheit mittel. Die Versionsverwaltung bewahrt den alten Code auf; die Korrektur entfernt die Zeilen.",',
    '      "options": [',
    '        {',
    '          "name": "minLines",',
    '          "description": "Mindestzahl aufeinanderfolgender auskommentierter Codezeilen."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "default-parameter",',
    '      "name": "Standardparameter statt Überladung",',
    '      "description": "Ein Parameter mit Vorgabewert (Anzahl: Integer = 10). Für Teams, die Überladungen bevorzugen: Vorgabewerte landen beim Aufrufer im Code, ändern sich nicht mit der Bibliothek und ' +
    'vertragen sich schlecht mit Überladungen. Gemeldet wird einmal je Deklaration (Klassenmitglied, interface-Teil, forward oder eine Routine nur im implementation-Teil); der Rumpf zu einer Deklaration ni' +
    'cht noch einmal. Die Schnellkorrektur fügt vor der Deklaration je weggelassenem Standardparameter am Ende eine Überladung ein, die mit dem Vorgabewert weiterreicht, entfernt die Vorgabewerte (auch im ' +
    'Rumpf wiederholte) und ergänzt overload. Keine Korrektur, wenn die Signatur von außen vorgegeben ist (virtual, dynamic, abstract, override, message, external, Interface-Typen), der Name als Wert benut' +
    'zt wird (@Routine, Methodenzeiger), es schon eine gleichnamige Überladung gibt, in bedingter Übersetzung oder wenn der Rumpf nicht eindeutig zu finden ist."',
    '    },',
    '{',
    '      "id": "empty-routine",',
    '      "name": "Leere Methode",',
    '      "description": "Eine Methode oder Routine, deren Rumpf weder eine Anweisung noch einen Kommentar (noch eine Compiler-Direktive) enthält. Entweder fehlt der Inhalt oder die Methode kann weg. Nich' +
    't gemeldet werden virtuelle und dynamische Methoden (Ersatz für abstract in Basisklassen), Nachrichten-Handler, Methoden von Klassen mit Interfaces (der Compiler verlangt jede Interface-Methode), Erei' +
    'gnis-Handler, die in der Formulardatei stehen (die IDE entfernt leere beim Speichern), und Rümpfe mit Kommentar, etwa Überschreibungen, die bewusst nichts tun. Schnellkorrekturen: Kommentar zwischen b' +
    'egin und end einfügen; Methode entfernen (Deklaration samt XML-Doku und Rumpf) nur bei privaten Methoden und Routinen ohne Deklaration im interface-Teil, die sonst nirgends in der Datei vorkommen und ' +
    'keine Signatur von außen erfüllen."',
    '    },',
    '{',
    '      "id": "trivial-accessor",',
    '      "name": "Zugriffsmethode liest bzw. setzt nur ein Feld",',
    '      "description": "Ein Getter, dessen Rumpf nur Result := FName; enthält (auch Exit(FName), Self.FName), oder ein Setter, dessen Rumpf nur FName := Value; enthält (mit refactoring.inlineAccessorEqu' +
    'alityCheck auch if FName <> Value then FName := Value;). Die Property kann direkt auf das Feld zeigen. Nur Methoden, die nicht virtual, dynamic, override oder abstract, keine class-Methoden, nicht übe' +
    'rladen oder generisch sind, keine Interface-Methode implementieren (auch nicht über eine Methodenzuordnung), keinen index haben und von keinem anderen Mitglied der Klasse benutzt werden; das Feld gehö' +
    'rt zur Klasse und hat den Typ der Property. Stumm, solange refactoring.inlineAccessorDiagnostic aus ist (Vorgabe) oder refactoring.inlineAccessor aus ist. Sicherheit mittel: Aufrufe in anderen Units s' +
    'ieht die Regel nicht. Keine Korrektur in der Regel; die Code-Aktion „Zugriffsmethode GetName durch Feld FName ersetzen“ an derselben Stelle prüft die Aufrufe mit der Referenzsuche und ersetzt."',
    '    },',
    '{',
    '      "id": "write-only-property",',
    '      "name": "Property ohne read",',
    '      "description": "Eine Property hat write, aber kein read. Sie lässt sich nicht im Objektinspektor anzeigen, nicht im Debugger lesen und verwirrt Aufrufer. Properties ohne Typ bleiben außen vor (s' +
    'ie veröffentlichen eine geerbte Property neu, deren read vom Vorfahren kommt), ebenso Properties mit einem Attribut aus allowAttributes (mit oder ohne Endung Attribute). Schnellkorrektur: read FName e' +
    'rgänzen, wenn der Typ ein Feld FName gleichen Typs deklariert. Das Lesen einer solchen Property meldet readonly-property-assigned.",',
    '      "options": [',
    '        {',
    '          "name": "allowAttributes",',
    '          "description": "Attribute, die eine Property ohne read erlauben."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "xmldoc-mismatch",',
    '      "name": "XMLDoc passt nicht zur Signatur",',
    '      "description": "Ein ///-Kommentar passt nicht zu seiner Deklaration oder ist kein wohlgeformtes XML, wie die Compilerwarnungen W1201 bis W1208 mit eingeschalteter XML-Dokumentation. Einen Code n' +
    'ennt die Meldung nur, wo dcc ihn meldet (#1383): bei Kommentaren im interface-Teil einer Unit (nur die dokumentiert dcc) und unter den XML-Fehlern nur bei einem fremden Zeichen hinter dem Tagnamen (W1' +
    '205); ''<'' mit folgendem Leerzeichen, unbekannte Entitäten, leere Attributwerte und offene Tags übersetzt Delphi 13 ohne Warnung. Gemeldet werden: <param> zu einem Parameter, den es nicht gibt; fehlend' +
    'e <param>, wenn der Block überhaupt Parameter beschreibt (wie W1208, „but other parameters do“); mit checkReturns <returns> an einer Routine ohne Ergebnis und fehlendes <returns> an einer Funktion, de' +
    'ren Block Parameter beschreibt. <inheritdoc/> ergänzt, was fehlt. Außerdem ''<'' und ''&'' außerhalb von Tags und Entitäten, unbekannte Entitäten, Attributwerte ohne Anführungszeichen, nicht geschlossene ' +
    'und überzählige Endtags sowie cref-Ziele, die es nicht gibt (W1206, nur mit Index und wenn jede Unit aus uses bekannt ist; generische Ziele, Unit-Namen und Typen mit unbekannten Vorfahren bleiben stil' +
    'l). Mit requirePublic zusätzlich public- und published-Methoden und -Properties von Typen im interface ohne ///-Kommentar (nicht override, nicht Properties ohne Typ). Schnellkorrekturen: unbekannte <p' +
    'aram> der Reihe nach auf die fehlenden umbenennen, die übrigen als leere Zeilen in Signaturreihenfolge ergänzen, überzählige <param> und <returns> an Prozeduren entfernen; Zeichen maskieren, Anführung' +
    'szeichen setzen, Endtag ergänzen oder entfernen, ein fremdes leeres Tag wie TList<T> als Text schreiben; cref auf das ähnlichste Symbol setzen; Kommentargerüst erzeugen.",',
    '      "options": [',
    '        {',
    '          "name": "requirePublic",',
    '          "description": "Öffentliche Member ohne XMLDoc melden."',
    '        },',
    '        {',
    '          "name": "checkReturns",',
    '          "description": "<returns> prüfen."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "missing-begin-end",',
    '      "name": "Bedingung oder Schleife ohne begin … end",',
    '      "description": "Der Rumpf von if … then, else, for, while oder with ist eine einzelne Anweisung ohne begin … end. Mit der Regel haben Bedingungen und Schleifen immer einen Block; eine später erg' +
    'änzte zweite Anweisung landet so nicht versehentlich außerhalb. else if bleibt erlaubt (das innere if braucht keinen eigenen Block); repeat … until, case … end, try … end und asm … end sind schon Blöc' +
    'ke. Eine leere Anweisung (if X then ;) meldet empty-statement. Rümpfe mit {$IFDEF} meldet die Regel nicht. Solange die Regel an ist, meldet redundant-begin-end nichts. Schnellkorrekturen: begin … end ' +
    'um die Anweisung setzen, für die ganze Methode oder für die ganze Datei, eingerückt nach den Formatierungseinstellungen; ein ; vor else wandert in den Block (kein E2153); mit format.elsePlacement \"sa' +
    'meLine\" steht else hinter dem neuen end (end else).",',
    '      "options": [',
    '        {',
    '          "name": "statements",',
    '          "description": "Geprüfte Anweisungen; case für die Zweige von case-Anweisungen ergänzen."',
    '        },',
    '        {',
    '          "name": "allowSingleLineExit",',
    '          "description": "Exit, Continue, Break und raise in derselben Zeile wie die Bedingung erlauben (if … then Exit;)."',
    '        },',
    '        {',
    '          "name": "allowSameLine",',
    '          "description": "Eine einzelne Anweisung in derselben Zeile wie Bedingung bzw. Schleifenkopf erlauben."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unused-public-member",',
    '      "name": "Öffentliches Mitglied wird im Projekt nie verwendet",',
    '      "description": "Eine public- oder published-Methode, -Konstante oder -Property (wahlweise auch protected-Mitglieder, Felder und Klassenvariablen) bzw. eine Routine, Konstante, ein Typ oder eine ' +
    'globale Variable im interface-Abschnitt einer Unit (Option unitKinds) wird in den Projekten der Projektgruppe nirgends verwendet. Die Suche läuft projektweit über den Symbolindex: Nur Dateien, deren V' +
    'erwendungen im Index den Namen enthalten, werden gelesen, und jedes Vorkommen wird über die Namensauflösung zugeordnet; ein Vorkommen, das sich nicht auflösen lässt, zählt als Verwendung. Namen in For' +
    'mulardateien (.dfm/.fmx) und in String-Literalen zählen als Verwendung. Gelten als verwendet: Interface-Umsetzungen und Mitglieder von Interfaces, Methoden mit virtual, dynamic, override, abstract ode' +
    'r message, Konstruktoren, Destruktoren, Operatoren, Enumeratoren, Default-Properties, implements, Mitglieder mit Attributen, published-Mitglieder von TPersistent-Nachfahren (Streaming), von Klassen au' +
    's RegisterComponents, RegisterClass oder RegisterClasses und von Testklassen, published-Methoden, solange eine Formulardatei nicht lesbar ist, Property-Zugriffsmethoden, exportierte Routinen, Klassenh' +
    'elfer und Mitglieder von Klassen mit unbekanntem Vorfahren. Still, solange Projekte laden oder der Index unvollständig ist, wenn eine Datei nicht lesbar ist, bei Units mit Include-Dateien und bei Unit' +
    's von Packages oder Bibliotheken (Nutzer außerhalb des Projekts), außer projectKinds lässt sie zu. Bei Typen zählen Vorkommen in der eigenen Deklaration und in den Rümpfen der eigenen Methoden (samt K' +
    'opf TTyp.Name) nicht; Typen aus RegisterComponents, RegisterClass oder RegisterClasses gelten als verwendet, bei Attributklassen (XyzAttribute) zählt auch die Kurzform [Xyz]. deadCode.keepAttributes u' +
    'nd deadCode.keepPatterns aus den Einstellungen gelten zusätzlich zu keepAttributes und keepPatterns. Korrektur: als bewusst öffentlich markieren (lsp-ignore-Kommentar).",',
    '      "options": [',
    '        {',
    '          "name": "visibilities",',
    '          "description": "Geprüfte Sichtbarkeiten: public, published, protected."',
    '        },',
    '        {',
    '          "name": "memberKinds",',
    '          "description": "Geprüfte Arten von Typmitgliedern: method, constant, property, field, classVar. Deklarationen auf Unit-Ebene richten sich nach unitKinds."',
    '        },',
    '        {',
    '          "name": "projectKinds",',
    '          "description": "Projektarten, deren Units geprüft werden: application, package, library. Packages und Bibliotheken haben Nutzer außerhalb der Projektgruppe und sind deshalb standardmäßig aus' +
    '."',
    '        },',
    '        {',
    '          "name": "unitLevel",',
    '          "description": "Auch Deklarationen des interface-Abschnitts einer Unit prüfen (Arten aus unitKinds)."',
    '        },',
    '        {',
    '          "name": "unitKinds",',
    '          "description": "Mit unitLevel geprüfte Arten auf Unit-Ebene: routine, constant, type, variable. Helfer werden nie gemeldet (sie werden über den erweiterten Typ verwendet)."',
    '        },',
    '        {',
    '          "name": "scope",',
    '          "description": "Wo nach Verwendungen gesucht wird: projectGroup (alle Projekte der Gruppe) oder project (nur die Projekte der Datei)."',
    '        },',
    '        {',
    '          "name": "testsCountAsUse",',
    '          "description": "Verwendungen in Testprojekten zählen; ist es aus, wird ein Mitglied, das nur Tests verwenden, als solches gemeldet."',
    '        },',
    '        {',
    '          "name": "stringLiteralsCountAsUse",',
    '          "description": "Der Name als String-Literal (''Name'') zählt als Verwendung (RTTI, MethodAddress, Skripte)."',
    '        },',
    '        {',
    '          "name": "keepAttributes",',
    '          "description": "Attribute am Mitglied oder seinem Typ, die es als verwendet markieren, z. B. \"Keep\" oder \"Api\"."',
    '        },',
    '        {',
    '          "name": "keepPatterns",',
    '          "description": "Namensmuster (* und ?) für Mitglieder, die immer als verwendet gelten, z. B. \"TPlugin.*\" oder \"*Callback\"."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unused-declaration",',
    '      "name": "Deklaration im implementation-Abschnitt wird nie verwendet",',
    '      "description": "Eine Routine, ein Typ, eine Konstante oder eine globale Variable aus dem implementation-Abschnitt einer Unit (bzw. aus einem Programm oder einer DLL) wird in der Unit nirgends ve' +
    'rwendet; der Compiler meldet das nicht. Jedes Vorkommen des Namens als Bezeichner zählt als Verwendung, auch in inaktiven Zweigen; nicht zählen die Deklarationen selbst (auch forward), Vorkommen im ei' +
    'genen Rumpf (Rekursion) und bei Typen Vorkommen in der eigenen Deklaration und in den Rümpfen der eigenen Methoden samt Kopf TTyp.Name. Bei Attributklassen (XyzAttribute) zählt auch die Kurzform [Xyz]' +
    '. Gelten als verwendet (Dienst, den auch unused-public-member nutzt): exportierte Routinen, Deklarationen mit Attributen, Namen aus deadCode.keepPatterns, Typen mit einem Attribut aus deadCode.keepAtt' +
    'ributes und Namen aus der Formulardatei. Rümpfe von Routinen des interface-Abschnitts prüft unused-public-member. Still bei Units mit Include-Dateien. Korrektur: als bewusst vorhanden markieren (lsp-i' +
    'gnore-Kommentar)."',
    '    },',
    '{',
    '      "id": "unused-unit",',
    '      "name": "Unit wird von keiner anderen Unit verwendet",',
    '      "description": "Eine Unit einer Anwendung verwendet keine andere Unit des Uses-Graphen: Höchstens Programme nennen sie im uses, und sie verwenden außerhalb ihres uses keinen ihrer Bezeichner (Ap' +
    'plication.CreateForm(TForm1, Form1) zählt als Verwendung). Units mit initialization- oder finalization-Abschnitt (Registrierungen, Seiteneffekte beim Start) gelten als verwendet, ebenso Units mit eine' +
    'r Klasse [TestFixture], die DUnitX per RTTI findet. Konfidenz mittel: Code außerhalb der Projektgruppe, Skripte oder zur Laufzeit geladene Packages können die Unit trotzdem nutzen. Still bei Units von' +
    ' Packages und DLLs (Nutzer außerhalb der Gruppe), solange projectKinds sie nicht erlaubt, ohne Projekte, solange Projekte laden oder der Index unvollständig ist, und für Units, die der Uses-Graph nich' +
    't kennt. Gemeldet am Unit-Namen im Kopf.",',
    '      "options": [',
    '        {',
    '          "name": "projectKinds",',
    '          "description": "Projektarten, deren Units geprüft werden: application, package, library."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "unused-uses",',
    '      "name": "Ungenutzte Unit im uses",',
    '      "description": "Aus der Unit eines uses-Eintrags wird nichts verwendet: Kein Bezeichner außerhalb der uses-Listen gleicht einem ihrer interface-Symbole (auch Mitgliedern) oder dem letzten Teil i' +
    'hres Namens. Dieselbe Analyse wie die abgeblendeten uses-Einträge im Editor (#621): Units, die der Index nicht kennt, Units mit initialization- oder finalization-Abschnitt, Units aus usesKeep oder der' +
    ' Option keep, Units, auf die die Formulardatei verweist (globale Variable der Unit mit dem Namen des Moduls in Connection = Form1.Connection, siehe dfm-reference-unit-missing), und Einträge in inaktiv' +
    'en {$IFDEF}-Zweigen bleiben. Konfidenz hoch. Sichere Korrektur: den Eintrag entfernen (mit seinem Komma; der einzige Eintrag entfernt das ganze uses), auch als Sammelkorrektur mit --fix unused-uses. S' +
    'till im Editor, wo dieselben Einträge abgeblendet erscheinen (das Abblenden folgt der Regel: off, exclude und lsp-ignore nehmen es mit weg), ohne Symbolindex (--no-index) und bei Syntaxfehlern.",',
    '      "options": [',
    '        {',
    '          "name": "keep",',
    '          "description": "Units, die nie als ungenutzt gelten, zusätzlich zu usesKeep; auch für das Abblenden im Editor und „uses aufräumen“."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "now-for-elapsed-time",',
    '      "name": "Laufzeit mit Now gemessen",',
    '      "description": "Eine Variable, der Now zugewiesen wird und die in derselben Routine danach in Now - Start, Ende - Start oder MilliSecondsBetween, SecondsBetween, MinutesBetween, HoursBetween, Da' +
    'ysBetween bzw. den …Span-Funktionen vorkommt: Die Laufzeit wird mit der Uhrzeit gemessen, grob aufgelöst und falsch bei Zeitumstellung oder Uhrabgleich. TStopwatch ist genau und monoton. Zuweisungen i' +
    'n einer anderen Routine (Felder) und im anderen Zweig von {$IFDEF} bleiben still. Konfidenz hoch. Schnellkorrektur, wenn die Variable eine lokale TDateTime ist (auch var Start := Now) und nur für Mill' +
    'iSecondsBetween, SecondsBetween oder MinutesBetween mit Now dient: TStopwatch.StartNew und ElapsedMilliseconds (div 1000 bzw. div 60000), die Variable heißt danach Uhr, wenn der Name frei ist, System.' +
    'Diagnostics kommt ins uses."',
    '    },',
    '{',
    '      "id": "money-as-float",',
    '      "name": "Geldbetrag als Gleitkommazahl",',
    '      "description": "Feld, Variable, Parameter oder Property, deren Name einen Geldbetrag bezeichnet (Option namePatterns), mit dem Typ Double, Single, Extended oder Real: Binäres Gleitkomma rundet C' +
    'ent-Beträge falsch (0.1 + 0.2), Currency rechnet sie exakt. Maßgeblich ist der letzte Namensteil (GesamtPreis, Nettobetrag, FNetto, Preise; nicht NettoGewicht); Sätze, Faktoren, Quoten, Anteile (Steue' +
    'rsatz, PriceFactor) und Prüfsummen bleiben still. Mehrdeutige Wörter (Amount, Summe, Sum, Total: Menge bzw. Summe von irgendetwas) zählen nur mit Geldbezug in Typ bzw. Routine: ein anderer Geldname, C' +
    'urrency oder Wörter wie Cent, Euro, Rabatt, Rechnung, Zahlung, Kosten (Lighten(AColor, AAmount: Double) bleibt still). Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingescha' +
    'ltet und minConfidence low ist. Schnellkorrektur, wenn alle Namen der Deklaration Geldbeträge sind: Typ Currency, bei Parametern auch im Kopf der Implementierung, bei Feldern und Properties auch die P' +
    'roperty bzw. das Feld hinter read und write; keine Korrektur, wenn ein Getter oder Setter mitwandern müsste. Mit checkRound meldet die Regel zusätzlich Round mit einem Geldbetrag im Argument (Banker''s' +
    ' Rounding: 2,5 wird 2).",',
    '      "options": [',
    '        {',
    '          "name": "namePatterns",',
    '          "description": "Namensteile, die einen Geldbetrag bezeichnen; Mehrzahl eingeschlossen."',
    '        },',
    '        {',
    '          "name": "checkRound",',
    '          "description": "Zusätzlich Round auf Geldbeträgen melden."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "string-if-chain",',
    '      "name": "Lange if-Kette über denselben String",',
    '      "description": "Eine if … else if-Kette vergleicht denselben String (Bezeichner oder A.B, keine Funktionsaufrufe) mit mindestens min Literalen: S = ''x'', ''x'' = S, SameText(S, ''x''), auch mit or ve' +
    'rknüpft, in mindestens zwei Zweigen (ein einzelnes if mit or bleibt still). case IndexStr(S, [...]) of oder ein Dictionary ist kürzer und schneller. Es zählen nur Vergleiche, die immer zusammen mit de' +
    'm Kopf übersetzt werden ({$IFDEF}-Zweige innerhalb der Kette nicht). Standard aus, Konfidenz hoch. Schnellkorrektur wie die Code-Aktion if-Kette in case umwandeln (#646): case IndexStr(…) of, IndexTex' +
    't(…) bei SameText, mit or verknüpfte Vergleiche teilen sich eine Marke, der Rest der Kette wird zum else, System.StrUtils kommt ins uses. Keine Korrektur bei Kommentaren oder Direktiven zwischen den Z' +
    'weigen, doppelten Literalen oder gemischtem = und SameText.",',
    '      "options": [',
    '        {',
    '          "name": "min",',
    '          "description": "Ab so vielen Vergleichen desselben Strings meldet die Regel; mindestens 2."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "prefer-case",',
    '      "name": "if-Kette lässt sich als case schreiben",',
    '      "description": "Eine if … else if-Kette mit mindestens min Zweigen (das abschließende else zählt mit) vergleicht denselben ordinalen Ausdruck (Ganzzahl, Zeichen, Aufzählung; ohne Seiteneffekte, ' +
    'kein Funktionsaufruf) mit Konstanten: X = a, a = X, X in [a, b..c], (X >= a) and (X <= b), auch mit or verknüpft. Die Marken sind Literale, Konstantenausdrücke, untypisierte Konstanten oder Aufzählung' +
    'swerte, ohne Doppelte und Überlappungen. Den Typ liefert die Namensauflösung; Ketten mit unbekanntem Typ und Ketten mit Direktiven bleiben still. Standard aus, Konfidenz hoch. Schnellkorrektur: die Co' +
    'de-Aktion „In case umwandeln“ (#646, refactoring.ifCase); begin … end nur, wo ein Zweig mehrere Anweisungen hat, Kommentare in den Zweigen bleiben.",',
    '      "options": [',
    '        {',
    '          "name": "min",',
    '          "description": "Ab so vielen Zweigen (das abschließende else eingeschlossen) meldet die Regel; mindestens 2."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "empty-finally",',
    '      "name": "Leerer finally-Block",',
    '      "description": "Ein finally-Block ohne Anweisung: Meist ist die Freigabe beim Umbau verloren gegangen. Steht direkt vor try X := T….Create, nennt die Meldung X.Free. Ein Block mit erklärendem Ko' +
    'mmentar gilt als bewusst und wird nicht gemeldet (wie bei empty-except); ein Block mit Compiler-Direktive ebenso nicht, weil ein anderer Zweig Code enthalten kann. Konfidenz hoch. Schnellkorrektur: tr' +
    'y, finally und end entfernen und den Rumpf ausrücken (wenn try, finally und end je allein auf ihrer Zeile stehen); als einzige Anweisung eines if-, while-, for-, with- oder case-Zweigs mit mehreren An' +
    'weisungen im Rumpf wird aus try begin."',
    '    },',
    '{',
    '      "id": "override-only-inherited",',
    '      "name": "override ruft nur inherited auf",',
    '      "description": "Eine überschreibende Methode, deren Rumpf nur die geerbte Methode aufruft: ein bloßes inherited;, inherited Name oder inherited Name(A, B) mit den eigenen Parametern in unverände' +
    'rter Reihenfolge, in Funktionen nur Result := inherited Name(…). Sie tut nichts Eigenes und täuscht ein geändertes Verhalten vor. Still, wenn die Methode die Sichtbarkeit der geerbten ändert (protecte' +
    'd zu public), ein Attribut, Standardwerte oder die Direktiven final, deprecated, experimental, platform, library oder reintroduce trägt, lokale Deklarationen, mehr als eine Anweisung, Kommentare oder ' +
    'bedingte Direktiven im Rumpf hat oder die überschriebene Methode unbekannt ist (Vorfahr nicht im Index; virtuelle Methoden von TObject gelten als public). Sicherheit hoch. Korrektur: Deklaration und R' +
    'umpf entfernen, samt XMLDoc-Kommentaren und der Leerzeile hinter dem Rumpf."',
    '    },',
    '{',
    '      "id": "inherited-without-ancestor",',
    '      "name": "inherited ohne Methode im Vorfahr",',
    '      "description": "Ein bloßes inherited; in einer Methode, die kein Vorfahr deklariert (neue Methode, kein override), tut nichts. Das deutet auf ein vergessenes override oder einen Tippfehler im Na' +
    'men. Nicht gemeldet: Message-Handler (inherited ruft dort DefaultHandler), Klassen- und statische Methoden, Konstruktoren und Destruktoren, override und reintroduce, inherited in anonymen Methoden, Vo' +
    'rfahren mit einem gleichnamigen Mitglied (auch nicht virtuell) und unbekannte Vorfahren. Vorfahren aus anderen Units liefert der Symbolindex; Methoden von TObject gelten als bekannt, wenn System nicht' +
    ' im Index steht. Sicherheit hoch. Korrektur: inherited entfernen, wenn es als eigene Anweisung in einem begin…end steht."',
    '    },',
    '{',
    '      "id": "redundant-jump",',
    '      "name": "Überflüssiges Exit oder Continue",',
    '      "description": "Ein bloßes Exit; als letzte Anweisung einer Routine oder anonymen Methode, oder ein bloßes Continue; als letzte Anweisung eines Schleifenrumpfs (for, for-in, while, repeat), auch' +
    ' im letzten Zweig eines if am Ende (der then-Zweig nur ohne else; then Continue else … bewacht eine else-if-Kette). Der Sprung ändert nichts. Nicht gemeldet: Exit mit Wert, Sprünge in try…finally oder' +
    ' try…except (der Sprung löst den finally-Teil bewusst aus), in case, qualifizierte Namen wie System.Continue, Anweisungen mit goto-Marke und Rümpfe mit bedingten Direktiven. Sicherheit hoch. Korrektur' +
    ': die Anweisung entfernen, wenn sie in einem begin…end oder direkt in repeat steht."',
    '    },',
    '{',
    '      "id": "method-without-self",',
    '      "name": "Methode braucht Self nicht",',
    '      "description": "Eine Methode einer Klasse oder eines Records nutzt weder Self noch Instanzmitglieder (Felder, Properties, Instanzmethoden, inherited). Sie ist nicht virtuell, hat kein Attribut u' +
    'nd ist nicht published (DUnitX-Tests und RTTI rufen sie an der Instanz auf), ist kein Ereignis der Formulardatei, implementiert kein Interface und wird nicht als Methodenzeiger verwendet. Experimentel' +
    'l: nur aktiv, wenn in atlas.json eingeschaltet; schweigt mit refactoring.methodKind aus. Schnellkorrektur: in eine class-Methode umwandeln (class … static mit refactoring.methodKindStatic); die Code-A' +
    'ktionen bieten außerdem Aufrufe über die Klasse, eine freie Routine und einen Record-Helper für den Typ des ersten Parameters, jeweils mit Vorschau aller geänderten Aufrufe."',
    '    }');

implementation

end.
