unit Cm.E2545;

// E2545 Cannot publish class property '%s' - only instance properties can be published
// Erwartet: E2545

interface

type
  TKlasse = class
  private
    class var FWert: Integer;
  published
    class property Wert: Integer read FWert; // <- E2545
  end;

implementation

end.
