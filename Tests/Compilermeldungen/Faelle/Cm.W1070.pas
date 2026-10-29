unit Cm.W1070;

// W1070 Use of untyped pointer can disrupt instance reference counts
// Erwartet: W1070
// Vermutung: Zuweisung eines untypisierten Zeigers an ein Interface.

interface

implementation

procedure Setzen(var AZiel: IInterface; AQuelle: Pointer);
begin
  Pointer(AZiel) := AQuelle;
  AZiel := IInterface(AQuelle); // <- W1070
end;

end.
