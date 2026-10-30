unit Cm.E2010b;

// E2010 Incompatible types: '%s' and '%s'
// Erwartet: E2010
// string + Integer (#1369).

interface

implementation

function Fall(AZahl: Integer): string;
begin
  Result := 'Anzahl: ' + AZahl; // <- E2010
end;

end.
