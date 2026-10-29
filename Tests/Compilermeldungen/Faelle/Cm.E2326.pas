unit Cm.E2326;

// E2326 Attribute '%s' can only be used once per target
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung.

interface

type
  TKlasse = class
  public
    [Weak] [Weak] FVerweis: TObject; // <- ohne Meldung
  end;

implementation

end.
