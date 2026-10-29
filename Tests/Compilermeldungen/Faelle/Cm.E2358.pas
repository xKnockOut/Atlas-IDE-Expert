unit Cm.E2358;

// E2358 Class constructors not allowed in class helpers
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Laut DccFaelle TR7 übersetzt dcc das; der Fall zeigt die aktuelle Lage.

interface

type
  THelfer = class helper for TObject
  public
    class constructor Create; // <- ohne Meldung
  end;

implementation

class constructor THelfer.Create;
begin
end;

end.
