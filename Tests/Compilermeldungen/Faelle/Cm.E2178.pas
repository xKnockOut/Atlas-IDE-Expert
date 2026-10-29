unit Cm.E2178;

// E2178 Dynamic methods and message handlers not allowed in OLE automation section
// Erwartet: E2178

interface

type
  TAuto = class
  automated
    procedure Machen; dynamic; // <- E2178
  end;

implementation

procedure TAuto.Machen;
begin
end;

end.
