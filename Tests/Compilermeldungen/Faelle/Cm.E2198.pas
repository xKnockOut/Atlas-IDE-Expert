unit Cm.E2198;

// E2198 %s cannot be applied to a long string
// Erwartet: E2008
// Delphi 13 meldet hier E2008 statt E2198.
// Vermutung; früher für SizeOf/High auf langen Strings.

interface

implementation

procedure Fall;
var
  mText: string;
  mZeiger: Pointer;
begin
  mText := 'abc';
  mZeiger := Ptr(mText); // <- E2008
end;

end.
