unit Cm.E2398;

// E2398 Class methods in record types must be static
// Erwartet: E2398

interface

type
  TRec = record
    class procedure Machen; // <- E2398
  end;

implementation

class procedure TRec.Machen;
begin
end;

end.
