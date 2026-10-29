unit Cm.E2054b;

// E2054 Illegal type in Write/Writeln statement
// Erwartet: E2054
// Gegenprobe zu type-kind-required (#1370): Record in Writeln.

interface

implementation

type
  TPunkt = record
    X, Y: Integer;
  end;

procedure Fall;
var
  mPunkt: TPunkt;
begin
  mPunkt := Default(TPunkt);
  Writeln(ErrOutput, mPunkt); // <- E2054
end;

end.
