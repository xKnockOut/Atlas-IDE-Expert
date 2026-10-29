unit Cm.H2369;

// H2369 Property accessor should be
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung; aus der .NET-Zeit (Get/Set-Namen).

interface

type
  TMitEigenschaft = class
  private
    function LiesWert: Integer;
  public
    property Wert: Integer read LiesWert; // <- ohne Meldung
  end;

implementation

function TMitEigenschaft.LiesWert: Integer;
begin
  Result := 0;
end;

end.
