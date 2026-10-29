unit Cm.E2169;

// E2169 Field definition not allowed after methods or properties
// Erwartet: E2169

interface

type
  TKlasse = class
  public
    procedure Machen;
    FWert: Integer; // <- E2169
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
