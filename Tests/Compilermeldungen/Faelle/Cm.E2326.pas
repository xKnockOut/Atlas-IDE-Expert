unit Cm.E2326;

// E2326 Attribute '%s' can only be used once per target
// Erwartet: E2326
// Vermutung.

interface

type
  TKlasse = class
  public
    [Weak] [Weak] FVerweis: TObject; // <- E2326
  end;

implementation

end.
