unit Cm.E2182;

// E2182 '%s' clause not allowed in OLE automation section
// Erwartet: E2182

interface

type
  TAuto = class
  private
    function GetWert(AIndex: Integer): Integer;
  automated
    property Wert: Integer index 1 read GetWert; // <- E2182
  end;

implementation

function TAuto.GetWert(AIndex: Integer): Integer;
begin
  Result := AIndex;
end;

end.
