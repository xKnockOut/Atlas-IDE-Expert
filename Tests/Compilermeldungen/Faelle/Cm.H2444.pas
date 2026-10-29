unit Cm.H2444;

// H2444 Inline function has not been expanded because accessing member is inaccessible
// Erwartet: H2444

interface

implementation

uses
  Cm.Hilfe.H2444;

function Rechne(AObjekt: TVerborgen): Integer;
begin
  Result := AObjekt.Wert; // <- H2444
end;

end.
