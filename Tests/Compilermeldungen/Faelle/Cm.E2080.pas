unit Cm.E2080;

// E2080 Procedure DISPOSE needs destructor
// Erwartet: E2080
// Vermutung; E2602 ist die neuere Form.

interface

implementation

procedure Fall;
var
  mZeiger: PInteger;
begin
  New(mZeiger);
  Dispose(mZeiger, Done); // <- E2080
end;

end.
