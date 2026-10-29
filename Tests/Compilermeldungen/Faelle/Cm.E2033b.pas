unit Cm.E2033b;

// E2033 Types of actual and formal var parameters must be identical
// Erwartet: E2033
// string an var AnsiString (#1369).

interface

implementation

procedure Lesen(var AText: AnsiString);
begin
end;

procedure Fall;
var
  mText: string;
begin
  mText := '';
  Lesen(mText); // <- E2033
end;

end.
