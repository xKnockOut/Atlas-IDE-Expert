unit Cm.E2357;

// E2357 PROCEDURE, FUNCTION, or CONSTRUCTOR expected
// Erwartet: E2357
// Vermutung zum Code.

interface

type
  TKlasse = class
  public
    class property; // <- E2357
  end;

implementation

end.
