unit Cm.E2562;

// E2562 Field identifier required
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2562.

interface

implementation

type
  TPunkt = record
    X, Y: Integer;
  end;

const
  cPunkt: TPunkt = (1, 2); // <- E2029

procedure Fall;
begin

end;

end.
