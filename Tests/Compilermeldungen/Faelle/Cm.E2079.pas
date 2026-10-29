unit Cm.E2079;

// E2079 Procedure NEW needs constructor
// Erwartet: E2467
// Delphi 13 meldet hier E2467 statt E2079.
// Vermutung; E2601 ist die neuere Form.

interface

implementation

procedure Fall;
var
  mZeiger: PInteger;
begin
  New(mZeiger, Init); // <- E2467
end;

end.
