unit Cm.E2601;

// E2601 Procedure NEW needs constructor identifier of '%s', but undeclared identifier '%s' found
// Erwartet: E2601

interface

type
  TAltObjekt = object
    Wert: Integer;
    constructor Init;
  end;

  PAltObjekt = ^TAltObjekt;

implementation

constructor TAltObjekt.Init;
begin
end;

procedure Fall;
var
  mObjekt: PAltObjekt;
begin
  New(mObjekt, Anlegen); // <- E2601
end;

end.
