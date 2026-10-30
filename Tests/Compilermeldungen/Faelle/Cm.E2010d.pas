unit Cm.E2010d;

// E2010 Incompatible types: '%s' and '%s'
// Erwartet: E2010
// Standardwert eines Parameters (#1369).

interface

implementation

procedure Zeigen(AZahl: Integer = 'a'); // <- E2010
begin
end;

end.
