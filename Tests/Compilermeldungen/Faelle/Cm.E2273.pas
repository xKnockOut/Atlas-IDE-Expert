unit Cm.E2273;

// E2273 No overloaded version of '%s' with this parameter list exists
// Erwartet: E2010
// Delphi 13 meldet hier E2010 statt E2273.
// Vermutung zum Code: Zuweisung einer Überladung an einen Prozedurtyp.

interface

implementation

procedure Nimm(AWert: Integer); overload;
begin
end;

procedure Nimm(const AText: string); overload;
begin
end;

procedure Fall;
var
  mRueckruf: procedure(AWert: Double);
begin
  mRueckruf := Nimm; // <- E2010
end;

end.
