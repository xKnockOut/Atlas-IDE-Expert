unit Cm.E2080;

// E2080 Procedure DISPOSE needs destructor
// Erwartet: E2019
// Delphi 13 meldet hier E2019 statt E2080.
// Vermutung; E2602 ist die neuere Form.

interface

implementation

procedure Fall;
var
  mZeiger: PInteger;
begin
  New(mZeiger);
  Dispose(mZeiger, Done); // <- E2019
end;

end.
