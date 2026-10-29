unit Cm.W1019;

// W1019 For loop control variable must be simple local variable
// Erwartet: W1019
// Laufvariable ist eine globale Variable.

interface

var
  GZaehler: Integer;

implementation

procedure Schleife;
begin
  for GZaehler := 0 to 2 do // <- W1019
    ;
end;

end.
