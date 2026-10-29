unit Cm.E2464;

// E2464 First parameter of Assign operator must be var parameter
// Erwartet: E2464

interface

type
  TRec = record
    Wert: Integer;
    class operator Assign(const [ref] AZiel: TRec; const [ref] AQuelle: TRec); // <- E2464
  end;

implementation

class operator TRec.Assign(const [ref] AZiel: TRec; const [ref] AQuelle: TRec);
begin
end;

end.
