unit Cm.E2239;

// E2239 Default parameter '%s' must be by-value or const
// Erwartet: E2239

interface

implementation

procedure Fall(var AWert: Integer = 0); // <- E2239
begin
end;

end.
