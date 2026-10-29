{$WARN IMMUTABLE_STRINGS ON}
unit Cm.W1068;

// W1068 Modifying strings in place may not be supported in the future
// Erwartet: W1068

interface

implementation

procedure Aendern(var AText: string);
begin
  AText[1] := 'x'; // <- W1068
end;

end.
