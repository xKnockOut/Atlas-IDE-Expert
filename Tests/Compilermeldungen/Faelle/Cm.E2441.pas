unit Cm.E2441;

// E2441 Inline function declared in interface section must not use local symbol '%s'
// Erwartet: E2441

interface

function Liefere: Integer; inline;

implementation

var
  GVerborgen: Integer;

function Liefere: Integer;
begin
  Result := GVerborgen; // <- E2441
end;

end.
