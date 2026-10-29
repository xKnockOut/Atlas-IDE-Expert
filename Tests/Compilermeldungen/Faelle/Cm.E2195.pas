unit Cm.E2195;

// E2195 Cannot initialize local variables
// Erwartet: E2195

interface

implementation

procedure Fall;
var
  mZahl: Integer = 1; // <- E2195
begin
end;

end.
