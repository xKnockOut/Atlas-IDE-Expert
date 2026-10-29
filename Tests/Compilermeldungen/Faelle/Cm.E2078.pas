unit Cm.E2078;

// E2078 Procedure FAIL only allowed in constructor
// Erwartet: E2078

interface

implementation

procedure Fall;
begin
  Fail; // <- E2078
end;

end.
