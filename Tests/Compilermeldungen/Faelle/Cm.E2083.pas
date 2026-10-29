unit Cm.E2083;

// E2083 Order of fields in record constant differs from declaration
// Erwartet: E2083

interface

type
  TPunkt = record
    X, Y: Integer;
  end;

implementation

const
  cPunkt: TPunkt = (Y: 1; X: 2); // <- E2083

end.
