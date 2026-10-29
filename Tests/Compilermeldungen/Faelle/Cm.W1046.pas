{$WARN UNSAFE_TYPE ON}
unit Cm.W1046;

// W1046 Unsafe type
// Erwartet: W1046

interface

implementation

procedure Zeiger;
var
  mZeiger: PInteger; // <- W1046
begin
  mZeiger := nil;
  if mZeiger = nil then
    Exit;
end;

end.
