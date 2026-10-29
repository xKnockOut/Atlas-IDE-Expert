unit Cm.E2094;

// E2094 Local procedure '%s' cannot be assigned to procedure variable
// Erwartet: E2094

interface

implementation

type
  TRueckruf = procedure;

procedure Aussen;
var
  mRueckruf: TRueckruf;

  procedure Innen;
  begin
  end;

begin
  mRueckruf := Innen; // <- E2094
  mRueckruf;
end;

end.
