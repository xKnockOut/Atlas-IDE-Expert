{$WARN UNSAFE_TYPE ON}
unit Cm.W1046;

// W1046 Unsafe type
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

procedure Zeiger;
var
  mZeiger: PInteger; // <- ohne Meldung
begin
  mZeiger := nil;
  if mZeiger = nil then
    Exit;
end;

end.
