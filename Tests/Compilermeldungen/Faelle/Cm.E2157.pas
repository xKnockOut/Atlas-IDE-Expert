{$ZEROBASEDSTRINGS OFF}
unit Cm.E2157;

// E2157 Element 0 inaccessible - use 'Length' or 'SetLength'
// Erwartet: E2157

interface

implementation

procedure Fall;
var
  mText: string;
  mZeichen: Char;
begin
  mText := 'abc';
  mZeichen := mText[0]; // <- E2157
end;

end.
