unit Cm.E2540;

// E2540 Cannot seal abstract type '%s'
// Erwartet: E2540
// Vermutung zum Code.

interface

type
  TKlasse = class sealed
  public
    procedure Machen; virtual; abstract; // <- E2540
  end;

implementation

end.
