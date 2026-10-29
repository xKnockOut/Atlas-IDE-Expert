unit Cm.E2467;

// E2467 Record or object type required
// Erwartet: E2467
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  with mZahl do // <- E2467
    ;
end;

end.
