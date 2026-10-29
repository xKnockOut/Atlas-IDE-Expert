unit Cm.H2368;

// H2368 Visibility of property accessor method should match property
// Erwartet: W1055
// Delphi 13 meldet hier W1055 statt H2368.
// Vermutung; aus der .NET-Zeit (CLS).

interface

type
  TMitEigenschaft = class
  public
    function GetWert: Integer;
  published
    property Wert: Integer read GetWert; // <- W1055
  end;

implementation

function TMitEigenschaft.GetWert: Integer;
begin
  Result := 0;
end;

end.
