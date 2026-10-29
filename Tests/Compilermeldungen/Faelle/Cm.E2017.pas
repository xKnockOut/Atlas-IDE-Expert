unit Cm.E2017;

// E2017 Pointer type required
// Erwartet: E2017

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl^ := 0; // <- E2017
end;

end.
