unit Cm.E2237;

// E2237 Parameter '%s' not allowed here due to default value
// Erwartet: E2237

interface

implementation

procedure Fall(AErster, AZweiter: Integer = 0); // <- E2237
begin
end;

end.
