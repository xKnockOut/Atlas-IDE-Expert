unit Cm.E2520;

// E2520 Result type of operator '%s' must be Boolean type
// Erwartet: E2520
// Laut DccFaelle OP1 übersetzt dcc das.

interface

type
  TRec = record
    class operator Equal(A, B: TRec): Integer; // <- E2520
  end;

implementation

class operator TRec.Equal(A, B: TRec): Integer;
begin
  Result := 0;
end;

end.
