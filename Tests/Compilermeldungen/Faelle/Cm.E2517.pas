unit Cm.E2517;

// E2517 Operator '%s' must take %d parameter(s)
// Erwartet: E2517

interface

type
  TRec = record
    class operator Add(A: TRec): TRec; // <- E2517
  end;

implementation

class operator TRec.Add(A: TRec): TRec;
begin
  Result := A;
end;

end.
