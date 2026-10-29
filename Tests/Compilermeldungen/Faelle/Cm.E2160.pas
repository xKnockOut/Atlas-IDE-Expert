unit Cm.E2160;

// E2160 Type not allowed in OLE Automation call
// Erwartet: E2160

interface

implementation

uses
  System.Variants;

type
  TPunkt = record
    X, Y: Integer;
  end;

procedure Fall;
var
  mObjekt: OleVariant;
  mPunkt: TPunkt;
begin
  mPunkt := Default(TPunkt);
  mObjekt := Unassigned;
  mObjekt.Machen(mPunkt); // <- E2160
end;

end.
