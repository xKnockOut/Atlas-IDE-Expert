unit Cm.H2457;

// H2457 Inline function has not been expanded because contained unit uses compiling unit indirectly
// Erwartet: H2457

interface

implementation

uses
  Cm.Hilfe.H2457;

function Rechne: Integer;
begin
  Result := Doppelt(2); // <- H2457
end;

end.
