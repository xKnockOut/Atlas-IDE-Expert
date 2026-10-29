unit Cm.H2443;

// H2443 Inline function has not been expanded because unit is not specified in USES list
// Erwartet: H2443

interface

implementation

uses
  Cm.Hilfe.H2443;

function Rechne: Integer;
begin
  Result := Doppelt(2); // <- H2443
end;

end.
