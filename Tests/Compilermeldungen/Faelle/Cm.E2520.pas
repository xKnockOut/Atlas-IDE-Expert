unit Cm.E2520;

// E2520 Result type of operator '%s' must be Boolean type
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Laut DccFaelle OP1 übersetzt dcc das.

interface

type
  TRec = record
    class operator Equal(A, B: TRec): Integer; // <- ohne Meldung
  end;

implementation

class operator TRec.Equal(A, B: TRec): Integer;
begin
  Result := 0;
end;

end.
