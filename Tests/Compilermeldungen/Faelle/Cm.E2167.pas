unit Cm.E2167;

// E2167 Abstract methods must be virtual or dynamic
// Erwartet: E2167

interface

type
  TKlasse = class
  public
    procedure Machen; abstract; // <- E2167
  end;

implementation

end.
