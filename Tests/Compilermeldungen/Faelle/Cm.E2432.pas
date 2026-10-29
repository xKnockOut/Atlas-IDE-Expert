unit Cm.E2432;

// E2432 %s cannot be applied to a rectangular dynamic array
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2432.
// Vermutung; .NET.

interface

implementation

procedure Fall;
var
  mFeld: array of array of Integer;
begin
  SetLength(mFeld, 2, 2);
  mFeld := Copy(mFeld, 0, 1, 1); // <- E2029
end;

end.
