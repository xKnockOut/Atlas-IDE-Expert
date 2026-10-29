unit Cm.E2089;

// E2089 Invalid typecast
// Erwartet: E2089

interface

implementation

procedure Fall;
var
  mText: string;
  mKlein: Byte;
begin
  mText := 'a';
  mKlein := Byte(mText); // <- E2089
end;

end.
