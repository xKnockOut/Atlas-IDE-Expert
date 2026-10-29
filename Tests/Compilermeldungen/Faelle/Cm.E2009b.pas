unit Cm.E2009b;

// E2009 Incompatible types: '%s'
// Erwartet: E2009
// Routine mit anderem Parametertyp an einen prozeduralen Typ (#1369).

interface

implementation

type
  TRueckruf = procedure(AWert: Integer);

procedure Nimm(const AText: string);
begin
end;

procedure Fall;
var
  mRueckruf: TRueckruf;
begin
  mRueckruf := Nimm; // <- E2009
  mRueckruf(1);
end;

end.
