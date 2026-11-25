unit Atlas.Common.Semantics.InferredTypes.TestSupport;

// Quelltexte für Tests der Typableitung (#453): Daten mit generischem
// Enumerator, Quelle mit Liste und Funktion, Nutzer mit Inline-Variablen,
// for-in und Inline-Konstante. Gemeinsam für Semantics.InferredTypes,
// Editing.ExplicitType und die Inlay Hints.

interface

const
  cDatenFile = 'C:\P\Daten.pas';
  cQuelleFile = 'C:\P\Quelle.pas';
  cNutzerFile = 'C:\P\Nutzer.pas';

  cUnitDaten =
    'unit Daten;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDaten = class'#10 +
    '  end;'#10 +
    '  TEnum<T> = class'#10 +
    '    function GetCurrent: T;'#10 +
    '    function MoveNext: Boolean;'#10 +
    '    property Current: T read GetCurrent;'#10 +
    '  end;'#10 +
    '  TListe<T> = class'#10 +
    '    function GetEnumerator: TEnum<T>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TEnum<T>.GetCurrent: T;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TEnum<T>.MoveNext: Boolean;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TListe<T>.GetEnumerator: TEnum<T>;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cUnitQuelle =
    'unit Quelle;'#10 +
    'interface'#10 +
    'uses Daten;'#10 +
    'var'#10 +
    '  Kunden: TListe<TDaten>;'#10 +
    'function Lade: TDaten;'#10 +
    'implementation'#10 +
    'function Lade: TDaten;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cUnitNutzer =
    'unit Nutzer;'#10 +                              // 0
    'interface'#10 +                                 // 1
    'uses Quelle;'#10 +                              // 2
    'implementation'#10 +                            // 3
    'procedure P;'#10 +                              // 4
    'var'#10 +                                       // 5
    '  Zahlen: TArray<Integer>;'#10 +                // 6
    '  Text: string;'#10 +                           // 7
    'begin'#10 +                                     // 8
    '  var X := Lade;'#10 +                          // 9
    '  for var Z in Zahlen do'#10 +                  // 10
    '    ;'#10 +                                     // 11
    '  for var K in Kunden do'#10 +                  // 12
    '    ;'#10 +                                     // 13
    '  for var C in Text do'#10 +                    // 14
    '    ;'#10 +                                     // 15
    '  const N = 5;'#10 +                            // 16
    '  for var T: Integer in Zahlen do'#10 +         // 17
    '    ;'#10 +                                     // 18
    'end;'#10 +                                      // 19
    'end.';

implementation

end.
