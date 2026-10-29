unit Cm.E2035;

// E2035 Not enough actual parameters
// Erwartet: E2035

interface

implementation

procedure Zwei(AErster, AZweiter: Integer);
begin
end;

procedure Fall;
begin
  Zwei(1); // <- E2035
end;

end.
