unit Dcc.VarParameter;

// #1328, Regel invalid-var-argument: Slice an einen var- oder out-Open-Array-Parameter
// (Spring4D Spring.pas, Spring.Benchmark).

interface

procedure Sortiere(var AWerte: array of Double);
procedure SortiereFeld;

implementation

{$R-}

type
  TAusschnitt = array[0..0] of Double;

procedure Fuelle(out AWerte: array of Double);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AWerte) do
    AWerte[mIndex] := 0;
end;

procedure Sortiere(var AWerte: array of Double);
var
  mMitte: Integer;
begin
  if Length(AWerte) < 2 then
    Exit;
  mMitte := Length(AWerte) div 2;
  Sortiere(Slice(AWerte, mMitte)); // IV1: Slice eines Open Arrays
  Sortiere(Slice(TAusschnitt(AWerte[mMitte]), Length(AWerte) - mMitte)); // IV2: Slice über Typumwandlung
end;

procedure SortiereFeld;
var
  mWerte: array[0..3] of Double;
begin
  FillChar(mWerte, SizeOf(mWerte), 0);
  Sortiere(Slice(mWerte, 2)); // IV3: Slice eines statischen Arrays
  Fuelle(Slice(mWerte, 2)); // IV4 (vorher VG1): Slice an einen out-Parameter
end;

end.
