unit Cm.E2082;

// E2082 TYPEOF can only be applied to object types with a VMT
// Erwartet: E2082

interface

implementation

procedure Fall;
var
  mZahl: Integer;
  mZeiger: Pointer;
begin
  mZahl := 1;
  mZeiger := TypeOf(mZahl); // <- E2082
end;

end.
