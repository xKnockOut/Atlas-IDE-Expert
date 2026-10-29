unit Cm.E2168;

// E2168 Field or method identifier expected
// Erwartet: E2168

interface

type
  TKlasse = class
  public
    property Wert: Integer read GibtEsNicht; // <- E2168
  end;

implementation

end.
