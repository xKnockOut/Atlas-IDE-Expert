unit Cm.E2602;

// E2602 Procedure DISPOSE needs destructor identifier of '%s', but undeclared identifier '%s' found
// Erwartet: E2602

interface

type
  TAltObjekt = object
    Wert: Integer;
    constructor Init;
    destructor Done;
  end;

  PAltObjekt = ^TAltObjekt;

implementation

constructor TAltObjekt.Init;
begin
end;

destructor TAltObjekt.Done;
begin
end;

procedure Fall;
var
  mObjekt: PAltObjekt;
begin
  New(mObjekt, Init);
  Dispose(mObjekt, Abbauen); // <- E2602
end;

end.
