unit Cm.E2461;

// E2461 Identifier '%s' is not an instance field
// Erwartet: E2356
// Delphi 13 meldet hier E2356 statt E2461.
// Gleicher Code wie E2356; dcc entscheidet, welche Meldung kommt.

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
