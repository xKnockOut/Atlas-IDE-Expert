{$WARN IMPLICIT_CONVERSION_LOSS ON}
unit Cm.W1072;

// W1072 Implicit conversion may lose significant digits
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

function Kuerzen(AWert: Int64): Single;
begin
  Result := AWert; // <- ohne Meldung
end;

end.
