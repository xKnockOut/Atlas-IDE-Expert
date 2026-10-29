unit Cm.E2292;

// E2292 '%s' must reference a property or field of class '%s'
// Erwartet: E2168
// Delphi 13 meldet hier E2168 statt E2292.
// Vermutung zum Code.

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert;
  end;

  TZweite = class
  public
    property Wert: Integer read TKlasse.FWert; // <- E2168
  end;

implementation

end.
