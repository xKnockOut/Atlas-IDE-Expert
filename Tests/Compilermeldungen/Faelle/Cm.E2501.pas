unit Cm.E2501;

// E2501 Inline function cannot call nested routine '%s'
// Erwartet: E2501

interface

implementation

function Aussen: Integer; inline;

  function Innen: Integer;
  begin
    Result := 1;
  end;

begin
  Result := Innen; // <- E2501
end;

end.
