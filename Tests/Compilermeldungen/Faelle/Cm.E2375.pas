unit Cm.E2375;

// E2375 PRIVATE or PROTECTED expected
// Erwartet: E2375

interface

type
  TKlasse = class
  strict public
    FWert: Integer; // <- E2375
  end;

implementation

end.
