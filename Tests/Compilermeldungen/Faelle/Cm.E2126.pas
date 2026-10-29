unit Cm.E2126;

// E2126 Cannot BREAK, CONTINUE or EXIT out of a FINALLY clause
// Erwartet: E2126

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  try
    mZahl := 1;
  finally
    Exit; // <- E2126
  end;
end;

end.
