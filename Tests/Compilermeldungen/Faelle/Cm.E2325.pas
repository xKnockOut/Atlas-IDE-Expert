unit Cm.E2325;

// E2325 Attribute '%s' is not valid on this target
// Erwartet: E2325
// Vermutung: [Volatile] ist nur an Feldern und Variablen erlaubt.

interface

type
  TKlasse = class
  public
    [Volatile] // <- E2325
    procedure Machen;
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
