{$J-}
unit Cm.E2197;

// E2197 Constant object cannot be passed as var parameter
// Erwartet: E2197

interface

implementation

const
  cZahl: Integer = 1;

procedure Erhoehen(var AWert: Integer);
begin
  AWert := AWert + 1;
end;

procedure Fall;
begin
  Erhoehen(cZahl); // <- E2197
end;

end.
