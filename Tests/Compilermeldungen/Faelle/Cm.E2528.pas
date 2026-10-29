unit Cm.E2528;

// E2528 Type parameters not allowed on this method
// Erwartet: E2528
// Vermutung zum Code.

interface

type
  TKlasse = class
  public
    constructor Create<T>; // <- E2528
  end;

implementation

constructor TKlasse.Create<T>;
begin
end;

end.
