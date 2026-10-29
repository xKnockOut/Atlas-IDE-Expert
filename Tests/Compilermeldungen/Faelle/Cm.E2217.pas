unit Cm.E2217;

// E2217 Published field '%s' not a class or interface type
// Erwartet: E2217

interface

type
  TKlasse = class
  published
    FWert: Integer; // <- E2217
  end;

implementation

end.
