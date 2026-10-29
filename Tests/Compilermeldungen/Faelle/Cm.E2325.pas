unit Cm.E2325;

// E2325 Attribute '%s' is not valid on this target
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung: [Volatile] ist nur an Feldern und Variablen erlaubt.

interface

type
  TKlasse = class
  public
    [Volatile] // <- ohne Meldung
    procedure Machen;
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
