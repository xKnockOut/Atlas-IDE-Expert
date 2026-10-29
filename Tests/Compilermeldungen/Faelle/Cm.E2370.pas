unit Cm.E2370;

// E2370 Cannot use inherited methods for interface property accessors
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Laut DccFaelle ID3 übersetzt dcc das inzwischen.

interface

type
  IBasis = interface
    function GetWert: Integer;
  end;

  IKind = interface(IBasis)
    property Wert: Integer read GetWert; // <- ohne Meldung
  end;

implementation

end.
