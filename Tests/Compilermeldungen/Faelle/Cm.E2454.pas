unit Cm.E2454;

// E2454 Slice standard function not allowed for VAR nor OUT argument
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Laut DccFaelle IV3 übersetzt dcc das; der Fall zeigt die aktuelle Lage.

interface

implementation

procedure Fuellen(var AWerte: array of Integer);
begin
end;

procedure Fall;
var
  mFeld: array[0..3] of Integer;
begin
  Fuellen(Slice(mFeld, 2)); // <- ohne Meldung
end;

end.
