unit Cm.W1002;

// W1002 Symbol is specific to a platform
// Erwartet: W1002

interface

implementation

procedure Alt; platform;
begin
end;

procedure Benutze;
begin
  Alt; // <- W1002
end;

end.
