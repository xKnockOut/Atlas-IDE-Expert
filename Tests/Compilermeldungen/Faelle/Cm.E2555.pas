unit Cm.E2555;

// E2555 Cannot capture symbol '%s'
// Erwartet: E2555

interface

implementation

type
  TRueckruf = reference to procedure;

procedure Fall(var AWert: Integer);
var
  mRueckruf: TRueckruf;
begin
  mRueckruf :=
    procedure
    begin
      AWert := 1; // <- E2555
    end;
  mRueckruf();
end;

end.
