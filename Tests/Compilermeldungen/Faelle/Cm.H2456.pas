unit Cm.H2456;

// H2456 Inline function has not been expanded because contained unit uses compiling unit
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

uses
  Cm.Hilfe.H2456;

function Rechne: Integer;
begin
  Result := Doppelt(2); // <- ohne Meldung
end;

end.
