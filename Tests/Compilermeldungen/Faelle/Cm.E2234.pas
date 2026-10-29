unit Cm.E2234;

// E2234 Getter or setter for property '%s' cannot be found
// Erwartet: E2234

interface

type
  TKlasse = class
  private
    function GetWert: string;
  public
    property Wert: Integer read GetWert; // <- E2234
  end;

implementation

function TKlasse.GetWert: string;
begin
  Result := '';
end;

end.
