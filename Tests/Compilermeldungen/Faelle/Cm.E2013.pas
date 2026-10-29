unit Cm.E2013;

// E2013 Type of expression must be INTEGER
// Erwartet: E2008
// Delphi 13 meldet hier E2008 statt E2013.
// Vermutung.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  Inc(mZahl, 1.5); // <- E2008
end;

end.
