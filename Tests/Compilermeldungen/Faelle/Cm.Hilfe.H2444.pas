unit Cm.Hilfe.H2444;

interface

type
  TVerborgen = class
  private
    FWert: Integer;
  public
    function Wert: Integer; inline;
  end;

implementation

function TVerborgen.Wert: Integer;
begin
  Result := FWert;
end;

end.
