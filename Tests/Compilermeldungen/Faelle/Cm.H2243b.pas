unit Cm.H2243b;

// H2243 Expression needs no Initialize/Finalize
// Erwartet: -
// Gegenfall (#1381): verwaltete Typen und das Ziel eines Zeigers brauchen Initialize/Finalize.

interface

implementation

procedure Fall(AZeiger: PString);
var
  mText: string;
  mFeld: TArray<Integer>;
begin
  mText := 'a';
  SetLength(mFeld, 1);
  Finalize(mText);
  Finalize(mFeld);
  Finalize(AZeiger^);
end;

end.
