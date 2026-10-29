unit Cm.E2191;

// E2191 EXPORTS allowed only at global scope
// Erwartet: E2191

interface

implementation

procedure Ziel;
begin
end;

procedure Fall;
exports // <- E2191
  Ziel;
begin
end;

end.
