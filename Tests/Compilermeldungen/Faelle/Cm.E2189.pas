unit Cm.E2189;

// E2189 Thread local variables cannot be local to a function
// Erwartet: E2189

interface

implementation

procedure Fall;
threadvar // <- E2189
  mZahl: Integer;
begin
end;

end.
