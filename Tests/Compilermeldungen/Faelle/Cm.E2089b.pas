unit Cm.E2089b;

// E2089 Invalid typecast
// Erwartet: E2089
// Gleitkommazahl in einen Ordinaltyp (#1369).

interface

implementation

function Fall(AWert: Double): Integer;
begin
  Result := Integer(AWert); // <- E2089
end;

end.
