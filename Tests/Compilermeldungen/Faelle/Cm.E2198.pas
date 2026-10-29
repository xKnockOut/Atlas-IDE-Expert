unit Cm.E2198;

// E2198 %s cannot be applied to a long string
// Erwartet: E2198
// Vermutung; früher für SizeOf/High auf langen Strings.

interface

implementation

procedure Fall;
var
  mText: string;
  mZeiger: Pointer;
begin
  mText := 'abc';
  mZeiger := Ptr(mText); // <- E2198
end;

end.
