unit Cm.E2572Gegen;

// E2572 RTTI visibility set constant expression of type System.TRttiVisibility expected
// Erwartet: -
// #1372: Gegenfall: Sichtbarkeiten, leere Menge, Konstante aus System.

interface

{$RTTI EXPLICIT METHODS([vcPublic, vcPublished]) FIELDS([]) PROPERTIES(DefaultPropertyRttiVisibility)}

type
  TDaten = class
  public
    Wert: Integer;
  end;

implementation

end.
