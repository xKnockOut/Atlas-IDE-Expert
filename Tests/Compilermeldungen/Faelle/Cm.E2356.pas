unit Cm.E2356;

// E2356 Property accessor must be an instance field or method
// Erwartet: E2356

interface

type
  TKlasse = class
  private
    class var FWert: Integer;
  public
    property Wert: Integer read FWert; // <- E2356
  end;

implementation

end.
