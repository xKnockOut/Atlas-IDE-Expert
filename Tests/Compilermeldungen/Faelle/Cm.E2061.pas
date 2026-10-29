unit Cm.E2061;

// E2061 Local class types not allowed
// Erwartet: E2059
// Delphi 13 meldet hier E2059 statt E2061.
// Vermutung zum Code: lokale Klasse.

interface

implementation

procedure Fall;
type
  TLokal = class // <- E2059
  end;
begin
end;

end.
