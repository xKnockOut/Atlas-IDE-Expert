unit Cm.W1009b;

// W1009 Redeclaration of '%s' hides a member in the base class
// Erwartet: W1009
// Zweiter Versuch: Property verdeckt ein Feld des Vorfahren.

interface

type
  TBasis = class
  public
    Wert: Integer;
  end;

  TKind = class(TBasis)
  private
    FText: string;
  public
    property Wert: string read FText; // <- W1009
  end;

implementation

end.
