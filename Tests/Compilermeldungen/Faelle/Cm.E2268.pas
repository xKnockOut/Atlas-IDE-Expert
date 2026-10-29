unit Cm.E2268;

// E2268 Parameters of this type cannot have default values
// Erwartet: E2268
// Vermutung zum Code.

interface

type
  TPunkt = record
    X, Y: Integer;
  end;

implementation

procedure Fall(APunkt: TPunkt = ()); // <- E2268
begin
end;

end.
