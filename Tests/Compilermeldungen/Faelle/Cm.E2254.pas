unit Cm.E2254;

// E2254 Overloaded procedure '%s' must be marked with the 'overload' directive
// Erwartet: E2254

interface

implementation

procedure Nimm(AWert: Integer); overload;
begin
end;

procedure Nimm(const AText: string); // <- E2254
begin
end;

end.
