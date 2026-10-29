unit Cm.E2351;

// E2351 Final methods must be virtual or dynamic
// Erwartet: E2351

interface

type
  TKlasse = class
  public
    procedure Machen; final; // <- E2351
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
