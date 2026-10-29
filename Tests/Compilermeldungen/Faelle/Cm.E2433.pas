unit Cm.E2433;

// E2433 Method declarations not allowed in anonymous record or local record type
// Erwartet: E2433

interface

implementation

procedure Fall;
type
  TLokal = record
    procedure Machen; // <- E2433
  end;
begin
end;

end.
