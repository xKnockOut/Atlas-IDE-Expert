unit Cm.H2456;

// H2456 Inline function has not been expanded because contained unit uses compiling unit
// Erwartet: H2456

interface

implementation

uses
  Cm.Hilfe.H2456;

function Rechne: Integer;
begin
  Result := Doppelt(2); // <- H2456
end;

end.
