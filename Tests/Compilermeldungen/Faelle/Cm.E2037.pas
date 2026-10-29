unit Cm.E2037;

// E2037 Declaration of '%s' differs from previous declaration
// Erwartet: E2037

interface

function Liefere: Integer;

implementation

function Liefere: string; // <- E2037
begin
  Result := '';
end;

end.
