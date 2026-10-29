unit Cm.E2097;

// E2097 BREAK or CONTINUE outside of loop
// Erwartet: E2097

interface

implementation

procedure Fall;
begin
  Break; // <- E2097
end;

end.
