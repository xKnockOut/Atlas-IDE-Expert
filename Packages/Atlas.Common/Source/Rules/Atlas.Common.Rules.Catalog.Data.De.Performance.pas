unit Atlas.Common.Rules.Catalog.Data.De.Performance;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDePerformance: array[0..39] of string = (
    '{',
    '      "id": "string-concat-in-loop",',
    '      "name": "String-Verkettung in einer Schleife",',
    '      "description": "Eine String-Variable wird in einer Schleife schrittweise verlängert. Delphi vergrößert Strings meist an Ort und Stelle, deshalb nur mit niedriger Konfidenz und standardmäßig aus;' +
    ' bei vielen Durchläufen ist TStringBuilder schneller. Still, wenn die Variable in jedem Durchlauf vorher neu gesetzt wird, direkt im Schleifenrumpf und nicht hinter then, else oder einer case-Marke (s' +
    'ie wächst dann nicht über die Schleife)."',
    '    },',
    '{',
    '      "id": "loop-invariant-call",',
    '      "name": "Teurer Aufruf in der Schleifenbedingung",',
    '      "description": "Die Bedingung von while und until wird bei jedem Durchlauf ausgewertet. Aufrufe wie Trim oder Format und Eigenschaften wie Lines.Text werden dort jedes Mal neu berechnet; besser ' +
    'einmal vor der Schleife. Die Grenzen von for werden nur einmal ausgewertet und nicht gemeldet, ebenso .Text als Feld (Record-Feld eines Typs derselben Datei oder laut Namensauflösung ein Feld bzw. ein' +
    'e Property, die ein Feld liest), eine Property, deren Empfänger die Schleife ändert (Items[I].Text), FileExists und DirectoryExists (Warten auf eine Datei) und Aufrufe, deren Argument die Schleife änd' +
    'ert (Zuweisung, Inc, Dec, Delete, SetLength, Include, Exclude). Standardmäßig aus."',
    '    },',
    '{',
    '      "id": "missing-begin-update",',
    '      "name": "Hinzufügen in einer Schleife ohne BeginUpdate",',
    '      "description": "Items.Add, Lines.Add und ähnliche Aufrufe in einer Schleife zeichnen das Steuerelement bei jedem Aufruf neu. Die Schleife mit BeginUpdate und try … finally EndUpdate umschließen.' +
    ' Still bei Menüs (TMenuItem hat kein BeginUpdate, auch über Felder wie FParts.Menu.Items, auch in Records, die in der Klasse verschachtelt sind), bei Listen ohne Steuerelement (TObjectList<T>, TList, ' +
    'TDictionary), bei Typen im Index ohne BeginUpdate und bei for-Schleifen mit höchstens 10 Durchläufen (feste Grenzen oder ein statisches Array derselben Datei). Standardmäßig aus."',
    '    },',
    '{',
    '      "id": "setlength-in-loop",',
    '      "name": "Array wächst in der Schleife um je ein Element",',
    '      "description": "SetLength(A, Length(A) + 1) in einer Schleife kopiert das dynamische Array bei jedem Durchlauf. Die Regel meldet nur, wenn A sicher ein dynamisches Array ist (array of, TArray<T>' +
    ', ein Array-Typ der Datei oder ein bekannter RTL-Typ wie TBytes), nie bei Strings. In einer for-Schleife ist die Anzahl bekannt: Die Meldung nennt sie, und ist A eine lokale Variable, die vor der Schl' +
    'eife nicht benutzt und darin nur als A[High(A)] bzw. A[Length(A) - 1] beschrieben wird, setzt die Schnellkorrektur die Länge einmal vor der Schleife und indiziert mit der Schleifenvariable. Sonst die ' +
    'Werte in einer TList<T> sammeln."',
    '    },',
    '{',
    '      "id": "managed-param-without-const",',
    '      "name": "Verwalteter Parameter ohne const",',
    '      "description": "Ein Wertparameter vom Typ String, Interface, dynamisches oder offenes Array oder ein Record der Datei ab minRecordSize Byte, den die Routine nie verändert. Jeder Aufruf zahlt Ref' +
    'erenzzählung bzw. Kopie; const spart beides. Verändert heißt: zugewiesen, ein Teil zugewiesen (Zeichen, Felder, Elemente), an var oder out übergeben, @Parameter, Methodenaufruf an einem Record, Laufva' +
    'riable einer for-Schleife. Die Regel meldet nur, wenn das sicher ist: Aufrufe mit unbekannter Signatur (Methoden ohne Symbolindex, Überladungen), with-Blöcke, Einfangen in anonymen Methoden, inherited' +
    ' ohne Namen und asm lassen sie schweigen. Virtuelle, dynamische, abstrakte und message-Methoden, Aufrufkonventionen, external- und exportierte Routinen, Methoden von Klassen mit Interfaces, published-' +
    'Methoden und als Wert benutzte Methoden (Ereignisse, @Routine, Formulardatei) bleiben außen vor, weil ihre Signatur von außen vorgegeben ist; Overrides nur mit ignoreOverrides = false und dann ohne Ko' +
    'rrektur. Die Korrektur ergänzt const in Rumpf und Deklaration und teilt Parametergruppen bei Bedarf. Mit den Projektdateien (IDE, MCP) zählt auch die Verwendung als Wert in Units, die diese Unit einbi' +
    'nden, etwa die Zuweisung an ein TFunc<string, …>, dessen Parameter kein const hat; ohne sie (Kommandozeile ohne Projekt) meldet solche Verweise nach der Korrektur der Compiler.",',
    '      "options": [',
    '        {',
    '          "name": "minRecordSize",',
    '          "description": "Record-Parameter ab dieser Größe in Byte melden."',
    '        },',
    '        {',
    '          "name": "ignoreOverrides",',
    '          "description": "Overrides nicht melden; ihre Signatur gibt der Vorfahr vor."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "case-insensitive-compare",',
    '      "name": "Vergleich über UpperCase oder LowerCase",',
    '      "description": "UpperCase(A) = UpperCase(B), LowerCase(A) <> ''x'', AnsiUpperCase(...) oder A.ToUpper = B.ToUpper erzeugt zwei Strings für einen Vergleich. SameText (AnsiSameText bei den Ansi-Funk' +
    'tionen und den Unicode-String-Helfern) ist kürzer und schneller. Ein Literal zählt nur, wenn die Umwandlung es nicht ändert; UpperCase(A) = LowerCase(B) und UpperCase(A) = ''ja'' bleiben unberührt, weil' +
    ' das andere Fehler sind. Ersetzt nicht die String-Helper-Modernisierung aus #71. Konfidenz hoch. Schnellkorrektur: SameText(A, B) bzw. not SameText(A, B)."',
    '    }');

implementation

end.
