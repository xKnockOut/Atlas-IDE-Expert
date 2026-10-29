unit Cm.E2361;

// E2361 Cannot access private symbol %s.%s
// Erwartet: E2361

interface

implementation

uses
  Cm.Hilfe.E2361;

procedure Fall;
var
  mObjekt: TVerborgen;
begin
  mObjekt := TVerborgen.Create;
  mObjekt.FWert := 1; // <- E2361
  mObjekt.Free;
end;

end.
