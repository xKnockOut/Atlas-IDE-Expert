unit Cm.E2180;

// E2180 Dispid '%d' already used by '%s'
// Erwartet: E2180

interface

type
  TAuto = class
  automated
    procedure Erste; dispid 1;
    procedure Zweite; dispid 1; // <- E2180
  end;

implementation

procedure TAuto.Erste;
begin
end;

procedure TAuto.Zweite;
begin
end;

end.
