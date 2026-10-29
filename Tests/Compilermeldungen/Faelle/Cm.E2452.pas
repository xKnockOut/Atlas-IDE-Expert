unit Cm.E2452;

// E2452 Unicode characters not allowed in published symbols
// Erwartet: E2452

interface

type
  TKlasse = class
  published
    procedure Größe; // <- E2452
  end;

implementation

procedure TKlasse.Größe;
begin
end;

end.
