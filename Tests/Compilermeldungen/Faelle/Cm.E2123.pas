unit Cm.E2123;

// E2123 PROCEDURE, FUNCTION, PROPERTY, or VAR expected
// Erwartet: E2123

interface

type
  TKlasse = class
  public
    class Wert: Integer; // <- E2123
  end;

implementation

end.
