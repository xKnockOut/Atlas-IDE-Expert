unit Cm.E2082;

// E2082 TYPEOF can only be applied to object types with a VMT
// Erwartet: E2019
// Delphi 13 meldet hier E2019 statt E2082.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
  mZeiger: Pointer;
begin
  mZahl := 1;
  mZeiger := TypeOf(mZahl); // <- E2019
end;

end.
