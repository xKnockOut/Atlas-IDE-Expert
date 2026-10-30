unit Cm.H2440b;

// H2440 Inline method visibility is not lower or same visibility of accessing member
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: dcc meldet H2440 erst beim Aufruf aus
// einer anderen Unit (Cm.Hilfe.H2440b), die die
// inline-Methode wegen des private-Felds nicht einsetzen kann.

interface

implementation

uses
  Cm.Hilfe.H2440b;

function Lesen(AObjekt: TMitInline): Integer;
begin
  Result := AObjekt.Wert; // <- ohne Meldung
end;

end.
