unit Cm.E2132;

// E2132 Default property must be an array property
// Erwartet: E2132

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert; default; // <- E2132
  end;

implementation

end.
