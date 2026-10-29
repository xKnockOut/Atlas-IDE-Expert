unit Cm.E2074;

// E2074 Label declared and referenced, but not set
// Erwartet: E2074

interface

implementation

procedure Fall;
label
  Ziel;
begin
  goto Ziel; // <- E2074
end;

end.
