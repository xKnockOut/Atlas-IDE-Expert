unit Cm.E2278;

// E2278 Cannot take address of local symbol %s
// Erwartet: E2278

interface

implementation

procedure Fall;
var
  mZahl: Integer;
const
  cZeiger: Pointer = @mZahl; // <- E2278
begin
  mZahl := 1;
end;

end.
