unit Cm.E2125;

// E2125 EXCEPT or FINALLY expected
// Erwartet: E2125

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  try
    mZahl := 1;
  end; // <- E2125
end;

end.
