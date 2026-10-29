unit Cm.E2452;

// E2452 Unicode characters not allowed in published symbols
// Erwartet: W1055
// Delphi 13 meldet hier W1055 statt E2452.

interface

type
  TKlasse = class
  published
    procedure Größe; // <- W1055
  end;

implementation

procedure TKlasse.Größe;
begin
end;

end.
