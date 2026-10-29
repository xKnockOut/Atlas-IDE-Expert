unit Cm.E2140;

// E2140 Duplicate message method index
// Erwartet: E2140

interface

type
  TKlasse = class
  public
    procedure Erste(var AWert); message 100;
    procedure Zweite(var AWert); message 100; // <- E2140
  end;

implementation

procedure TKlasse.Erste(var AWert);
begin
end;

procedure TKlasse.Zweite(var AWert);
begin
end;

end.
