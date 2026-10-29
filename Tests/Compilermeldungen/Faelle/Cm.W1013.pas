unit Cm.W1013;

// W1013 Constant 0 converted to NIL
// Erwartet: W1013
// Vermutung: Vorgabewert 0 für einen Klassenparameter.

interface

implementation

procedure Nehmen(AObjekt: TObject = 0); // <- W1013
begin
  AObjekt.Free;
end;

end.
