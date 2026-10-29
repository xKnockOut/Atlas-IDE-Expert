unit Cm.E2461;

// E2461 Identifier '%s' is not an instance field
// Erwartet: E2461
// Gleicher Code wie E2356; dcc entscheidet, welche Meldung kommt.

interface

type
  TKlasse = class
  private
    class var FWert: Integer;
  public
    property Wert: Integer read FWert; // <- E2461
  end;

implementation

end.
