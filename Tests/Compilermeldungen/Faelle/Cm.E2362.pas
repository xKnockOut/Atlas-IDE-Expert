unit Cm.E2362;

// E2362 Cannot access protected symbol %s.%s
// Erwartet: E2362

interface

implementation

uses
  Cm.Hilfe.E2361;

procedure Fall;
var
  mObjekt: TVerborgen;
begin
  mObjekt := TVerborgen.Create;
  mObjekt.FGeschuetzt := 1; // <- E2362
  mObjekt.Free;
end;

end.
