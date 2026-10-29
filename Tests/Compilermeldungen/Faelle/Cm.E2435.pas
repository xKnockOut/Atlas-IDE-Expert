unit Cm.E2435;

// E2435 Class member declarations not allowed in anonymous record or local record type
// Erwartet: E2435

interface

implementation

procedure Fall;
type
  TLokal = record
    class var Zaehler: Integer; // <- E2435
  end;
begin
end;

end.
