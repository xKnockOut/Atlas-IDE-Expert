unit Cm.F2069d;

// F2069 Line too long (more than 1023 characters)
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: eine Zeile mit 1100 Zeichen aus
// Bezeichnern und Operatoren, ohne Literal.

interface

implementation

function Summe(AWert: Integer): Integer;
begin
  Result := AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert + AWert; // <- ohne Meldung
end;

end.
