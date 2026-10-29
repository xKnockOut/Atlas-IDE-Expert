unit Cm.E2267;

// E2267 Previous declaration of '%s' was not marked with the 'overload' directive
// Erwartet: E2267

interface

implementation

procedure Nimm(AWert: Integer);
begin
end;

procedure Nimm(const AText: string); overload; // <- E2267
begin
end;

end.
