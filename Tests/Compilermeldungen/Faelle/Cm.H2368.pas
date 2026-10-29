unit Cm.H2368;

// H2368 Visibility of property accessor method should match property
// Erwartet: H2368
// Vermutung; aus der .NET-Zeit (CLS).

interface

type
  TMitEigenschaft = class
  public
    function GetWert: Integer;
  published
    property Wert: Integer read GetWert; // <- H2368
  end;

implementation

function TMitEigenschaft.GetWert: Integer;
begin
  Result := 0;
end;

end.
