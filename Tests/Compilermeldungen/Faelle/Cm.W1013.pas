unit Cm.W1013;

// W1013 Constant 0 converted to NIL
// Erwartet: E2010
// Delphi 13 meldet hier E2010 statt W1013.
// Vermutung: Vorgabewert 0 für einen Klassenparameter.

interface

implementation

procedure Nehmen(AObjekt: TObject = 0); // <- E2010
begin
  AObjekt.Free;
end;

end.
