unit Cm.W1009c;

// W1009 Redeclaration hides a member in the base class
// Erwartet: W1009
// Vermutung (#1383): Feld verdeckt ein Feld des Vorfahren (Cm.W1009: Feld verdeckt Property, still).

interface

type
  TBasis = class
  public
    Wert: Integer;
  end;

  TKind = class(TBasis)
  public
    Wert: string; // <- W1009
  end;

implementation

end.
