unit Cm.E2439;

// E2439 Inline function must not have open array argument
// Erwartet: E2439
// Delphi erlaubt das inzwischen womöglich.

interface

implementation

function Summe(const AWerte: array of Integer): Integer; inline; // <- E2439
begin
  Result := Length(AWerte);
end;

end.
