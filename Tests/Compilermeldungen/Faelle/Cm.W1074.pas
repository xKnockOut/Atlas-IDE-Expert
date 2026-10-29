unit Cm.W1074;

// W1074 Unknown custom attribute
// Erwartet: W1074

interface

type
  TMitAttribut = class
  public
    [Unbekannt] // <- W1074
    procedure Machen;
  end;

implementation

procedure TMitAttribut.Machen;
begin
end;

end.
