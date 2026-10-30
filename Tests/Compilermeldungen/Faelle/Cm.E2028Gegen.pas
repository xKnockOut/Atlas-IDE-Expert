unit Cm.E2028Gegen;

// E2028 Sets may have at most 256 elements
// Erwartet: -
// #1372: Gegenfall: Mengen bis 256 Elemente.

interface

type
  TFarbe = (Rot, Gruen, Blau);
  TFarben = set of TFarbe;
  TZahlen = set of Byte;
  TVoll = set of 0..255;
  TKlein = set of 10..20;

implementation

end.
