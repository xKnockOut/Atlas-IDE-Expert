unit Cm.E2186;

// E2186 Published Real property '%s' must be Single, Real, Double or Extended
// Erwartet: E2186
// Plattform: Win32

interface

type
  TKlasse = class
  private
    FWert: Real48;
  published
    property Wert: Real48 read FWert; // <- E2186
  end;

implementation

end.
