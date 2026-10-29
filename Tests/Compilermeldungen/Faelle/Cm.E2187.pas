unit Cm.E2187;

// E2187 Size of published set '%s' is >4 bytes
// Erwartet: E2187

interface

type
  TGrosseMenge = set of 0..100;

  TKlasse = class
  private
    FMenge: TGrosseMenge;
  published
    property Menge: TGrosseMenge read FMenge; // <- E2187
  end;

implementation

end.
