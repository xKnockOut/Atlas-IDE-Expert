unit Cm.E2370;

// E2370 Cannot use inherited methods for interface property accessors
// Erwartet: E2370
// Laut DccFaelle ID3 übersetzt dcc das inzwischen.

interface

type
  IBasis = interface
    function GetWert: Integer;
  end;

  IKind = interface(IBasis)
    property Wert: Integer read GetWert; // <- E2370
  end;

implementation

end.
