unit Cm.E2127;

// E2127 'GOTO %s' leads into or out of TRY statement
// Erwartet: E2127

interface

implementation

procedure Fall;
label
  Ziel;
begin
  goto Ziel; // <- E2127
  try
Ziel:
  finally
  end;
end;

end.
