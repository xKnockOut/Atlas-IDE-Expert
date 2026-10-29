unit Cm.E2307;

// E2307 NEW standard function expects a dynamic array type identifier
// Erwartet: E2307
// Vermutung; .NET-Form von New.

interface

implementation

procedure Fall;
var
  mFeld: array of Integer;
begin
  mFeld := New(Integer, 3); // <- E2307
end;

end.
