unit Cm.W1035;

// W1035 Return value of function might be undefined
// Erwartet: W1035

interface

implementation

function Liefere(AWert: Integer): Integer;
begin
  if AWert > 0 then
    Result := AWert;
end; // <- W1035

end.
