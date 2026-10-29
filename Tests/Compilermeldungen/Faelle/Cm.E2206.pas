unit Cm.E2206;

// E2206 Property overrides not allowed in interface type
// Erwartet: E2206

interface

type
  IBasis = interface
    function GetWert: Integer;
    property Wert: Integer read GetWert;
  end;

  IKind = interface(IBasis)
    property Wert; // <- E2206
  end;

implementation

end.
