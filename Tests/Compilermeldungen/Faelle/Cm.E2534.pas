unit Cm.E2534;

// E2534 Class constructor must not be virtual, dynamic nor message
// Erwartet: E2534

interface

type
  TKlasse = class
  public
    class constructor Create; virtual; // <- E2534
  end;

implementation

class constructor TKlasse.Create;
begin
end;

end.
