unit Cm.W1044;

// W1044 Suspicious typecast
// Erwartet: W1044

interface

implementation

procedure Zeiger;
var
  mText: string;
  mZeiger: PAnsiChar;
begin
  mText := 'abc';
  mZeiger := PAnsiChar(mText); // <- W1044
  if mZeiger = nil then
    Exit;
end;

end.
