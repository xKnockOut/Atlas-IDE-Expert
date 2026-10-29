unit Cm.E2218;

// E2218 Published method '%s' contains an unpublishable type
// Erwartet: E2218

interface

type
  TKlasse = class
  published
    procedure Machen(AZeiger: PInteger); // <- E2218
  end;

implementation

procedure TKlasse.Machen(AZeiger: PInteger);
begin
end;

end.
