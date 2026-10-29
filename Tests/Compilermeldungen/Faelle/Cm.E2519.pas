unit Cm.E2519;

// E2519 First parameter type of operator '%s' and result type must be identical
// Erwartet: E2519

interface

type
  TRec = record
    class operator Inc(A: TRec): Integer; // <- E2519
  end;

implementation

class operator TRec.Inc(A: TRec): Integer;
begin
  Result := 0;
end;

end.
