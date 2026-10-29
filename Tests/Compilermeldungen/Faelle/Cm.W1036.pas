unit Cm.W1036;

// W1036 Variable might not have been initialized
// Erwartet: W1036

interface

implementation

function Liefere: Integer;
var
  mWert: Integer;
begin
  Result := mWert; // <- W1036
end;

end.
