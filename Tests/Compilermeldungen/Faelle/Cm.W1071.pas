{$WARN IMPLICIT_INTEGER_CAST_LOSS ON}
unit Cm.W1071;

// W1071 Implicit integer cast with potential data loss
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

function Kuerzen(AWert: Int64): Integer;
begin
  Result := AWert; // <- ohne Meldung
end;

end.
