unit Cm.E2556;

// E2556 Type of procedure result or untyped parameter cannot be used as type argument
// Erwartet: E2003
// Delphi 13 meldet hier E2003 statt E2556.
// Vermutung zum Code.

interface

type
  TBehaelter<T> = class
  end;

implementation

procedure Fall(var AWert);
var
  mBehaelter: TObject;
begin
  mBehaelter := TBehaelter<AWert>.Create; // <- E2003
  mBehaelter.Free;
end;

end.
