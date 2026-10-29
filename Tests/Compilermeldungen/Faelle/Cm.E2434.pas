unit Cm.E2434;

// E2434 Property declarations not allowed in anonymous record or local record type
// Erwartet: E2434

interface

implementation

procedure Fall;
type
  TLokal = record
    FWert: Integer;
    property Wert: Integer read FWert; // <- E2434
  end;
begin
end;

end.
