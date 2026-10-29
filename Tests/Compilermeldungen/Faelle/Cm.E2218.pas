unit Cm.E2218;

// E2218 Published method '%s' contains an unpublishable type
// Erwartet: W1055
// Delphi 13 meldet hier W1055 statt E2218.

interface

type
  TKlasse = class
  published
    procedure Machen(AZeiger: PInteger); // <- W1055
  end;

implementation

procedure TKlasse.Machen(AZeiger: PInteger);
begin
end;

end.
