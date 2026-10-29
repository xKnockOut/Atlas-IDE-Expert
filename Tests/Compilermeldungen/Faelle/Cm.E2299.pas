unit Cm.E2299;

// E2299 Property required
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2299.
// Vermutung.

interface

type
  TKlasse = class
  public
    property; // <- E2029
  end;

implementation

end.
