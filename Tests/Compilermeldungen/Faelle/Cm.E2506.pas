unit Cm.E2506;

// E2506 Method of parameterized type declared in interface section must not use local symbol '%s'
// Erwartet: E2506

interface

type
  TBehaelter<T> = class
  public
    function Liefere: Integer;
  end;

implementation

var
  GVerborgen: Integer;

function TBehaelter<T>.Liefere: Integer;
begin
  Result := GVerborgen; // <- E2506
end;

end.
