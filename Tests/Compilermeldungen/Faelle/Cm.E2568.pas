unit Cm.E2568;

// E2568 Can't create new instance without CONSTRUCTOR constraint in type parameter declaration
// Erwartet: E2568

interface

type
  TBehaelter<T: class> = class
  public
    function Neu: T;
  end;

implementation

function TBehaelter<T>.Neu: T;
begin
  Result := T.Create; // <- E2568
end;

end.
