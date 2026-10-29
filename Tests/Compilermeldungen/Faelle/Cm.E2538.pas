unit Cm.E2538;

// E2538 DEFAULT standard function not allowed for this type
// Erwartet: E2538
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mDatei: TextFile;
begin
  mDatei := Default(TextFile); // <- E2538
end;

end.
