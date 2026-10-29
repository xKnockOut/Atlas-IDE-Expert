unit Dcc.VarParameter.Gegen;

// #1328, Gegentests zu invalid-var-argument: Hier soll dcc melden.

interface

procedure Teste;

implementation

const
  cGrenze = 3;

procedure Erhoehe(var AWert: Integer);
begin
  Inc(AWert);
end;

procedure Teste;
begin
  Erhoehe(cGrenze); // VG2: Konstante an einen var-Parameter
  Erhoehe(cGrenze + 1); // VG3: Ausdruck an einen var-Parameter
end;

end.
