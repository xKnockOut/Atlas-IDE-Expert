unit Cm.E2282;

// E2282 Property setters cannot take var parameters
// Erwartet: E2282

interface

type
  TKlasse = class
  private
    procedure SetWert(var AWert: Integer);
  public
    property Wert: Integer write SetWert; // <- E2282
  end;

implementation

procedure TKlasse.SetWert(var AWert: Integer);
begin
end;

end.
