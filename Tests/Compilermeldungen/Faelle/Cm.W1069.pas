{$WARN MOBILE_DELPHI ON}
unit Cm.W1069;

// W1069 Feature will not be available in mobile Delphi compiler
// Erwartet: W1069
// Vermutung; in neueren Versionen womöglich entfallen.

interface

implementation

function Text: AnsiString; // <- W1069
begin
  Result := 'a';
end;

end.
