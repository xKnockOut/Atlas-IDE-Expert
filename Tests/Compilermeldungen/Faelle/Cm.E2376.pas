unit Cm.E2376;

// E2376 STATIC can only be used on non-virtual class methods
// Erwartet: E2376

interface

type
  TKlasse = class
  public
    class procedure Machen; virtual; static; // <- E2376
  end;

implementation

class procedure TKlasse.Machen;
begin
end;

end.
