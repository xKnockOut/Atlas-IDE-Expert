unit Cm.E2174;

// E2174 '%s' not previously declared as a PROPERTY
// Erwartet: E2008
// Delphi 13 meldet hier E2008 statt E2174.
// Vermutung zum Code: Array-Property mit Feld.

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert[AIndex: Integer]: Integer read FWert; // <- E2008
  end;

implementation

end.
