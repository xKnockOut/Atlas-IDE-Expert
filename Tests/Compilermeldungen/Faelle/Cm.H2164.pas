unit Cm.H2164;

// H2164 Variable '%s' is declared but never used
// Erwartet: H2164

interface

implementation

procedure Machen;
var
  mUnbenutzt: Integer; // <- H2164
begin
end;

end.
