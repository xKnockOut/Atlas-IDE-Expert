unit Cm.E2030;

// E2030 Duplicate case label
// Erwartet: E2030

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  case mZahl of
    1: mZahl := 2;
    1: mZahl := 3; // <- E2030
  end;
end;

end.
