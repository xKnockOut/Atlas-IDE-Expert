unit Cm.E2449;

// E2449 Inlined nested routine '%s' cannot access outer scope variable '%s'
// Erwartet: E2449

interface

implementation

function Aussen: Integer;
var
  mWert: Integer;

  function Innen: Integer; inline;
  begin
    Result := mWert; // <- E2449
  end;

begin
  mWert := 1;
  Result := Innen;
end;

end.
