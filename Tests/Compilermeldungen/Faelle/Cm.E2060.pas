unit Cm.E2060;

// E2060 Class and interface types only allowed in type section
// Erwartet: E2058
// Delphi 13 meldet hier E2058 statt E2060.

interface

implementation

procedure Fall;
var
  mObjekt: class // <- E2058
  end;
begin

end;

end.
