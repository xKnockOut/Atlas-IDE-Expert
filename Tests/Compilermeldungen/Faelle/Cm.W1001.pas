unit Cm.W1001;

// W1001 Symbol is specific to a library
// Erwartet: W1001

interface

implementation

procedure Alt; library;
begin
end;

procedure Benutze;
begin
  Alt; // <- W1001
end;

end.
