unit Cm.E2093;

// E2093 Label '%s' is not declared in current procedure
// Erwartet: E2093

interface

implementation

procedure Aussen;
label
  Ziel;

  procedure Innen;
  begin
    goto Ziel; // <- E2093
  end;

begin
  Innen;
Ziel:
end;

end.
