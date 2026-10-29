unit Cm.E2430;

// E2430 for-in statement cannot operate on collection type '%s'
// Erwartet: E2430

interface

implementation

procedure Fall;
var
  mZahl: Integer;
  mWert: Integer;
begin
  mZahl := 1;
  for mWert in mZahl do // <- E2430
    ;
end;

end.
