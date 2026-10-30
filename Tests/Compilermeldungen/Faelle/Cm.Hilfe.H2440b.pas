unit Cm.Hilfe.H2440b;

interface

type
  TMitInline = class
  strict private
    FWert: Integer;
  public
    function Wert: Integer; inline;
  end;

implementation

function TMitInline.Wert: Integer;
begin
  Result := FWert;
end;

end.
