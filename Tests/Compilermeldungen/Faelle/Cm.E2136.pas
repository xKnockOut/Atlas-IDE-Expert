unit Cm.E2136;

// E2136 No definition for abstract method allowed
// Erwartet: E2136

interface

type
  TKlasse = class
  public
    procedure Machen; virtual; abstract;
  end;

implementation

procedure TKlasse.Machen; // <- E2136
begin
end;

end.
