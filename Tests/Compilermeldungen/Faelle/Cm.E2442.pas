unit Cm.E2442;

// E2442 Inline directive not allowed in constructor or destructor
// Erwartet: E2442

interface

type
  TKlasse = class
  public
    constructor Create; inline; // <- E2442
  end;

implementation

constructor TKlasse.Create;
begin
end;

end.
