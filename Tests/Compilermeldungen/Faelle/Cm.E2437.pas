unit Cm.E2437;

// E2437 Constant declarations not allowed in anonymous record or local record type
// Erwartet: E2437

interface

implementation

procedure Fall;
type
  TLokal = record
  const
    cWert = 1; // <- E2437
  end;
begin
end;

end.
