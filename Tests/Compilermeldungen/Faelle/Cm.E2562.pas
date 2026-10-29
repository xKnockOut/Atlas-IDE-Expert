unit Cm.E2562;

// E2562 Field identifier required
// Erwartet: E2562

interface

implementation

type
  TPunkt = record
    X, Y: Integer;
  end;

const
  cPunkt: TPunkt = (1, 2); // <- E2562

procedure Fall;
begin

end;

end.
