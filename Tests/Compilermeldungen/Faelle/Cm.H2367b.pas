unit Cm.H2367b;

// H2367 Case of property accessor method should be
// Erwartet: -
// Mit -J meldet dcc nur W1031 (Paket wird nicht geschrieben), ohne Datei.
// Schalter: -JPHNE
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: dcc meldet H2367 nur beim Erzeugen von
// C++-Headern (-JPHNE); Cm.H2367 ohne Schalter
// bleibt still.

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
