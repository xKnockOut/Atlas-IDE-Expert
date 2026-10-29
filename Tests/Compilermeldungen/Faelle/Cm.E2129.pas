unit Cm.E2129;

// E2129 Cannot assign to a read-only property
// Erwartet: E2129

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert;
  end;

implementation

procedure Fall(AObjekt: TKlasse);
begin
  AObjekt.Wert := 1; // <- E2129
end;

end.
