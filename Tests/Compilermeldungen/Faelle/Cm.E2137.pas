unit Cm.E2137;

// E2137 Method '%s' not found in base class
// Erwartet: E2137

interface

type
  TKlasse = class
  public
    procedure Machen; override; // <- E2137
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
