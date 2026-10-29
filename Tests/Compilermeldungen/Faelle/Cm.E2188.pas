unit Cm.E2188;

// E2188 Published property '%s' cannot be of type %s
// Erwartet: E2188

interface

type
  TFeld = array[0..2] of Integer;

  TKlasse = class
  private
    FFeld: TFeld;
  published
    property Feld: TFeld read FFeld; // <- E2188
  end;

implementation

end.
