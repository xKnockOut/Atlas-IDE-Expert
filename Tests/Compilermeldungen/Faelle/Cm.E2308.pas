unit Cm.E2308;

// E2308 Need to specify at least one dimension for NEW of dynamic array
// Erwartet: E2255
// Delphi 13 meldet hier E2255 statt E2308.
// Vermutung; .NET-Form von New.

interface

implementation

type
  TFeld = array of Integer;

procedure Fall;
var
  mFeld: TFeld;
begin
  mFeld := New(TFeld); // <- E2255
end;

end.
