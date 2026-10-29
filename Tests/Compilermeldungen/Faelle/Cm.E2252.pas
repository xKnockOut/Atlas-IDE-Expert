unit Cm.E2252;

// E2252 Method '%s' with identical parameters already exists
// Erwartet: E2252

interface

implementation

procedure Nimm(AWert: Integer); overload;
begin
end;

procedure Nimm(AZahl: Integer); overload; // <- E2252
begin
end;

end.
