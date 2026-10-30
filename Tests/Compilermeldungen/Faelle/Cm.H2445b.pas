unit Cm.H2445b;

// H2445 Inline function has not been expanded because its unit is specified in USES statement of IMPLEMENTATION section
// Erwartet: -
// Gegenfall (#1381): die Unit der inline-Funktion steht im uses des interface-Teils.

interface

uses
  Cm.Hilfe.H2445;

function Rechne: Integer; inline;

implementation

function Rechne: Integer;
begin
  Result := Doppelt(2);
end;

end.
