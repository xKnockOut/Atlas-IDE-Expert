unit Cm.E2130;

// E2130 Cannot read a write-only property
// Erwartet: E2130

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert: Integer write FWert;
  end;

implementation

function Fall(AObjekt: TKlasse): Integer;
begin
  Result := AObjekt.Wert; // <- E2130
end;

end.
