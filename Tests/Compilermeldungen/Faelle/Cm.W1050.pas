unit Cm.W1050;

// W1050 WideChar reduced to byte char in set expressions
// Erwartet: W1050

interface

implementation

function IstZiffer(AZeichen: Char): Boolean;
begin
  Result := AZeichen in ['0'..'9']; // <- W1050
end;

end.
