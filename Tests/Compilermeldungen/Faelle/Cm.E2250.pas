unit Cm.E2250;

// E2250 There is no overloaded version of '%s' that can be called with these arguments
// Erwartet: E2250

interface

implementation

procedure Nimm(AWert: Integer); overload;
begin
end;

procedure Nimm(const AWert: string); overload;
begin
end;

procedure Fall;
begin
  Nimm(1.5); // <- E2250
end;

end.
