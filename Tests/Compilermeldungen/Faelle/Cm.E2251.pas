unit Cm.E2251;

// E2251 Ambiguous overloaded call to '%s'
// Erwartet: E2251

interface

implementation

procedure Nimm(AWert: Integer; AText: string = ''); overload;
begin
end;

procedure Nimm(AWert: Integer; AZahl: Integer = 0); overload;
begin
end;

procedure Fall;
begin
  Nimm(1); // <- E2251
end;

end.
