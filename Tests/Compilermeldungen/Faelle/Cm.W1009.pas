unit Cm.W1009;

// W1009 Redeclaration hides a member in the base class
// Erwartet: W1009

interface

type
  TBasis = class
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert;
  end;

  TKind = class(TBasis)
  public
    Wert: string; // <- W1009
  end;

implementation

end.
