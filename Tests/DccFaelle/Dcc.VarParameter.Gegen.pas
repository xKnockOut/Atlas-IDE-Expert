unit Dcc.VarParameter.Gegen;

// #1328, Gegentests zu invalid-var-argument: Hier soll dcc melden.

interface

procedure Teste;

implementation

const
  cGrenze = 3;

procedure Fuelle(out AWerte: array of Double);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AWerte) do
    AWerte[mIndex] := 0;
end;

procedure Erhoehe(var AWert: Integer);
begin
  Inc(AWert);
end;

procedure Teste;
var
  mWerte: array[0..3] of Double;
begin
  Fuelle(Slice(mWerte, 2)); // VG1: Slice an einen out-Parameter
  Erhoehe(cGrenze); // VG2: Konstante an einen var-Parameter
  Erhoehe(cGrenze + 1); // VG3: Ausdruck an einen var-Parameter
end;

end.
