unit Cm.H2367;

// H2367 Case of property accessor method should be
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung: dcc prüft das nur für Getter/Setter mit Get/Set-Präfix in anderer Schreibweise.

interface

type
  TMitEigenschaft = class
  private
    FWert: Integer;
    function getwert: Integer;
  public
    property Wert: Integer read getwert; // <- ohne Meldung
  end;

implementation

function TMitEigenschaft.getwert: Integer;
begin
  Result := FWert;
end;

end.
