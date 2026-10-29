unit Cm.E2147;

// E2147 Property '%s' does not exist in base class
// Erwartet: E2147

interface

type
  TKlasse = class
  public
    property Wert; // <- E2147
  end;

implementation

end.
