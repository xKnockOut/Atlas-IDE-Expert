unit Cm.E2360;

// E2360 Class constructors cannot have parameters
// Erwartet: E2360

interface

type
  TKlasse = class
  public
    class constructor Create(AWert: Integer); // <- E2360
  end;

implementation

class constructor TKlasse.Create(AWert: Integer);
begin
end;

end.
