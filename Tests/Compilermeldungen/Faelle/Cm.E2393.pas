unit Cm.E2393;

// E2393 Invalid operator declaration
// Erwartet: E2393

interface

type
  TRec = record
    class operator Unbekannt(A: TRec): TRec; // <- E2393
  end;

implementation

class operator TRec.Unbekannt(A: TRec): TRec;
begin
  Result := A;
end;

end.
