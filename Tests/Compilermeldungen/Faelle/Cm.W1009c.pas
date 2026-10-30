unit Cm.W1009c;

// W1009 Redeclaration hides a member in the base class
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: Feld verdeckt ein Feld des Vorfahren
// (Cm.W1009: Feld verdeckt Property, still).

interface

type
  TBasis = class
  public
    Wert: Integer;
  end;

  TKind = class(TBasis)
  public
    Wert: string; // <- ohne Meldung
  end;

implementation

end.
