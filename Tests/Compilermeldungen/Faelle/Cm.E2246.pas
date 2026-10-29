unit Cm.E2246;

// E2246 Need to specify at least one dimension for SetLength of dynamic array
// Erwartet: E2246

interface

implementation

procedure Fall;
var
  mFeld: array of Integer;
begin
  SetLength(mFeld); // <- E2246
end;

end.
