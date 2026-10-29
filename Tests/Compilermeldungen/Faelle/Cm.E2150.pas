unit Cm.E2150;

// E2150 Bad argument type in variable type array constructor
// Erwartet: E2150

interface

implementation

type
  TPunkt = record
    X, Y: Integer;
  end;

procedure Nimm(const AWerte: array of const);
begin
end;

procedure Fall;
var
  mPunkt: TPunkt;
begin
  mPunkt := Default(TPunkt);
  Nimm([mPunkt]); // <- E2150
end;

end.
