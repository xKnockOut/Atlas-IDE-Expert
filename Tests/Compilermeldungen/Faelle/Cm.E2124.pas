unit Cm.E2124;

// E2124 Instance member '%s' inaccessible here
// Erwartet: E2124

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    class function Wert: Integer;
  end;

implementation

class function TKlasse.Wert: Integer;
begin
  Result := FWert; // <- E2124
end;

end.
