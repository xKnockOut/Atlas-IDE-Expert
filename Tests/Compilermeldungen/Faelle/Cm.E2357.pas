unit Cm.E2357;

// E2357 PROCEDURE, FUNCTION, or CONSTRUCTOR expected
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2357.
// Vermutung zum Code.

interface

type
  TKlasse = class
  public
    class property; // <- E2029
  end;

implementation

end.
