unit Cm.E2181;

// E2181 Redeclaration of property not allowed in OLE automation section
// Erwartet: E2181

interface

type
  TBasis = class
  private
    FWert: Integer;
  automated
    property Wert: Integer read FWert;
  end;

  TKind = class(TBasis)
  automated
    property Wert; // <- E2181
  end;

implementation

end.
