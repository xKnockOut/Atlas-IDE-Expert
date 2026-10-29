unit Cm.E2145;

// E2145 Re-raising an exception only allowed in exception handler
// Erwartet: E2145

interface

implementation

procedure Fall;
begin
  raise; // <- E2145
end;

end.
