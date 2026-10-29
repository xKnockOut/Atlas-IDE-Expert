unit Cm.E2281;

// E2281 Type not allowed in Variant Dispatch call
// Erwartet: E2281

interface

implementation

uses
  System.Variants;

procedure Fall;
var
  mObjekt: Variant;
  mZeiger: Pointer;
begin
  mObjekt := Unassigned;
  mZeiger := nil;
  mObjekt.Machen(mZeiger); // <- E2281
end;

end.
