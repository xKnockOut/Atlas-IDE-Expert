unit Cm.E2423;

// E2423 Void type not usable in this context
// Erwartet: H2077
// Delphi 13 meldet hier H2077 statt E2423.
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mZeiger: Pointer;
begin
  mZeiger := nil;
  if SizeOf(mZeiger^) > 0 then // <- H2077
    Exit;
end;

end.
