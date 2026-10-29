unit Cm.E2177;

// E2177 Constructors and destructors not allowed in OLE automation section
// Erwartet: E2177

interface

type
  TAuto = class
  automated
    constructor Create; // <- E2177
  end;

implementation

constructor TAuto.Create;
begin
end;

end.
