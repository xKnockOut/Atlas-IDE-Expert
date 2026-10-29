{$J-}
unit Cm.E2064;

// E2064 Left side cannot be assigned to
// Erwartet: E2064

interface

implementation

const
  cZahl: Integer = 1;

procedure Fall;
begin
  cZahl := 2; // <- E2064
end;

end.
