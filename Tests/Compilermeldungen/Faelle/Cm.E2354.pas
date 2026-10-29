unit Cm.E2354;

// E2354 String element cannot be passed to var parameter
// Erwartet: E2354

interface

implementation

procedure Aendern(var AZeichen: Char);
begin
  AZeichen := 'x';
end;

procedure Fall;
var
  mText: string;
begin
  mText := 'abc';
  Aendern(mText[1]); // <- E2354
end;

end.
