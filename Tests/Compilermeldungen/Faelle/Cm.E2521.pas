unit Cm.E2521;

// E2521 Operator '%s' must take one '%s' type in parameter or result type
// Erwartet: E2521

interface

type
  TRec = record
    class operator Implicit(A: Integer): string; // <- E2521
  end;

implementation

class operator TRec.Implicit(A: Integer): string;
begin
  Result := '';
end;

end.
