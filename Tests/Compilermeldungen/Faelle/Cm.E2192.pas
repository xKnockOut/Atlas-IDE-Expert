unit Cm.E2192;

// E2192 Constants cannot be used as open array arguments
// Erwartet: E2192
// Vermutung zum Code.

interface

implementation

procedure Fuellen(var AWerte: array of Integer);
begin
end;

procedure Fall;
begin
  Fuellen([1, 2]); // <- E2192
end;

end.
