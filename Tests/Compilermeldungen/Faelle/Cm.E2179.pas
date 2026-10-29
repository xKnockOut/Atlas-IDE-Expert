unit Cm.E2179;

// E2179 Only register calling convention allowed in OLE automation section
// Erwartet: E2179

interface

type
  TAuto = class
  automated
    procedure Machen; stdcall; // <- E2179
  end;

implementation

procedure TAuto.Machen;
begin
end;

end.
