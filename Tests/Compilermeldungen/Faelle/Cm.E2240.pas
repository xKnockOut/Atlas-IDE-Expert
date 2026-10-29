unit Cm.E2240;

// E2240 $EXTERNALSYM and $NODEFINE not allowed for '%s'; only global symbols
// Erwartet: E2003
// Delphi 13 meldet hier E2003 statt E2240.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
  {$EXTERNALSYM mZahl} // <- E2003
begin
  mZahl := 1;
end;

end.
