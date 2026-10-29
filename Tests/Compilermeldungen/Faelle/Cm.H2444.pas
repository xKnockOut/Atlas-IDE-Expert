unit Cm.H2444;

// H2444 Inline function has not been expanded because accessing member is inaccessible
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

uses
  Cm.Hilfe.H2444;

function Rechne(AObjekt: TVerborgen): Integer;
begin
  Result := AObjekt.Wert; // <- ohne Meldung
end;

end.
