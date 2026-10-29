unit Cm.W1015;

// W1015 FOR-Loop variable cannot be passed as var parameter
// Erwartet: W1015

interface

implementation

procedure Erhoehen(var AWert: Integer);
begin
  AWert := AWert + 1;
end;

procedure Schleife;
var
  mIndex: Integer;
begin
  for mIndex := 0 to 2 do
    Erhoehen(mIndex); // <- W1015
end;

end.
