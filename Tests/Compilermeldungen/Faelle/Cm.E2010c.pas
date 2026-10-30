unit Cm.E2010c;

// E2010 Incompatible types: '%s' and '%s'
// Erwartet: E2010
// Argument eines Wertparameters (#1369).

interface

implementation

procedure Zeigen(AZahl: Integer);
begin
end;

procedure Fall;
begin
  Zeigen('abc'); // <- E2010
end;

end.
