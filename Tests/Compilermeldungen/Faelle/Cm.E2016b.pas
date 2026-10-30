unit Cm.E2016b;

// E2016 Array type required
// Erwartet: E2016
// Gegenprobe zu type-kind-required (#1370): Index auf einem Zeichen.

interface

implementation

procedure Fall;
var
  mZeichen: Char;
begin
  mZeichen := 'a';
  mZeichen[1] := 'b'; // <- E2016
end;

end.
