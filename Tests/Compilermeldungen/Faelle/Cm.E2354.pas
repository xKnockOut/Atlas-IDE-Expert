unit Cm.E2354;

// E2354 String element cannot be passed to var parameter
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

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
  Aendern(mText[1]); // <- ohne Meldung
end;

end.
