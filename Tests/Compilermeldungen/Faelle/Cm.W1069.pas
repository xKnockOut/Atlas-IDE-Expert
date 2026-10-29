{$WARN MOBILE_DELPHI ON}
unit Cm.W1069;

// W1069 Feature will not be available in mobile Delphi compiler
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung; in neueren Versionen womöglich entfallen.

interface

implementation

function Text: AnsiString; // <- ohne Meldung
begin
  Result := 'a';
end;

end.
