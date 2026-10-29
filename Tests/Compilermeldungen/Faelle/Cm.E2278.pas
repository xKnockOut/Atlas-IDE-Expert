unit Cm.E2278;

// E2278 Cannot take address of local symbol %s
// Erwartet: F2084
// Delphi 13 meldet hier F2084 statt E2278.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
const
  cZeiger: Pointer = @mZahl; // <- F2084
begin
  mZahl := 1;
end;

end.
