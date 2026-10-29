unit Cm.E2176;

// E2176 Illegal type in OLE automation section
// Erwartet: E2176

interface

type
  TPunkt = record
    X, Y: Integer;
  end;

  TAuto = class
  automated
    procedure Machen(APunkt: TPunkt); // <- E2176
  end;

implementation

procedure TAuto.Machen(APunkt: TPunkt);
begin
end;

end.
