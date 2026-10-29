unit Cm.E2052;

// E2052 Unterminated string
// Erwartet: E2052

interface

implementation

procedure Fall;
var
  mText: string;
begin
  mText := 'offen; // <- E2052
end;

end.
