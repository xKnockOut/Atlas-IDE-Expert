unit Cm.E2252;

// E2252 Method '%s' with identical parameters already exists
// Erwartet: E2004
// Delphi 13 meldet hier E2004 statt E2252.

interface

implementation

procedure Nimm(AWert: Integer); overload;
begin
end;

procedure Nimm(AZahl: Integer); overload; // <- E2004
begin
end;

end.
