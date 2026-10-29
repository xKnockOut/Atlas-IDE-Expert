unit Cm.E2015;

// E2015 Operator not applicable to this operand type
// Erwartet: E2015

interface

implementation

procedure Fall;
var
  mText: string;
begin
  mText := 'abc';
  mText := mText - 'a'; // <- E2015
end;

end.
