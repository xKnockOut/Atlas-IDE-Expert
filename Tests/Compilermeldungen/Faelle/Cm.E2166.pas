unit Cm.E2166;

// E2166 Unnamed arguments must precede named arguments in OLE Automation call
// Erwartet: E2166

interface

implementation

uses
  System.Variants;

procedure Fall;
var
  mObjekt: OleVariant;
begin
  mObjekt := Unassigned;
  mObjekt.Machen(Wert := 1, 2); // <- E2166
end;

end.
