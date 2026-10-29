unit Cm.E2034;

// E2034 Too many actual parameters
// Erwartet: E2034

interface

implementation

procedure Eins(AWert: Integer);
begin
end;

procedure Fall;
begin
  Eins(1, 2); // <- E2034
end;

end.
