unit Cm.E2518;

// E2518 Operator '%s' must take least one '%s' type in parameters
// Erwartet: E2518

interface

type
  TRec = record
    class operator Add(A, B: Integer): Integer; // <- E2518
  end;

implementation

class operator TRec.Add(A, B: Integer): Integer;
begin
  Result := A + B;
end;

end.
