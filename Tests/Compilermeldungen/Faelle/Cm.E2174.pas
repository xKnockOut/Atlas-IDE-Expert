unit Cm.E2174;

// E2174 '%s' not previously declared as a PROPERTY
// Erwartet: E2174
// Vermutung zum Code: Array-Property mit Feld.

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert[AIndex: Integer]: Integer read FWert; // <- E2174
  end;

implementation

end.
