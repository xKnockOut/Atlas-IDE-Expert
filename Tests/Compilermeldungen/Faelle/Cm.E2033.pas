unit Cm.E2033;

// E2033 Types of actual and formal var parameters must be identical
// Erwartet: E2033

interface

implementation

procedure Erhoehen(var AWert: Integer);
begin
  AWert := AWert + 1;
end;

procedure Fall;
var
  mKlein: Byte;
begin
  mKlein := 1;
  Erhoehen(mKlein); // <- E2033
end;

end.
