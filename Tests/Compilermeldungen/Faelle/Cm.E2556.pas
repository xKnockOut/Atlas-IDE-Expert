unit Cm.E2556;

// E2556 Type of procedure result or untyped parameter cannot be used as type argument
// Erwartet: E2556
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
  mBehaelter := TBehaelter<AWert>.Create; // <- E2556
  mBehaelter.Free;
end;

end.
