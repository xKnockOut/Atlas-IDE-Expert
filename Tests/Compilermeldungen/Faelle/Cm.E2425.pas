unit Cm.E2425;

// E2425 Inline methods must not be virtual nor dynamic
// Erwartet: E2425

interface

type
  TKlasse = class
  public
    procedure Machen; virtual; inline; // <- E2425
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
