unit Cm.H2445;

// H2445 Inline function has not been expanded because its unit is specified in USES statement of IMPLEMENTATION section
// Erwartet: H2445

interface

function Rechne: Integer; inline;

implementation

uses
  Cm.Hilfe.H2445;

function Rechne: Integer;
begin
  Result := Doppelt(2); // <- H2445
end;

end.
