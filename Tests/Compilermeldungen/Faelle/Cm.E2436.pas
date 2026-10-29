unit Cm.E2436;

// E2436 Type declarations not allowed in anonymous record or local record type
// Erwartet: E2436

interface

implementation

procedure Fall;
type
  TLokal = record
  type
    TInnen = Integer; // <- E2436
  end;
begin
end;

end.
