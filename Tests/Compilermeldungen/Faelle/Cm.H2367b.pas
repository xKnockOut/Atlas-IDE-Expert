unit Cm.H2367b;

// H2367 Case of property accessor method should be
// Erwartet: H2367
// Schalter: -JPHNE
// Vermutung (#1383): dcc meldet H2367 nur beim Erzeugen von C++-Headern (-JPHNE); Cm.H2367 ohne Schalter
// bleibt still.

interface

type
  TMitEigenschaft = class
  private
    FWert: Integer;
    function getwert: Integer;
  public
    property Wert: Integer read getwert; // <- H2367
  end;

implementation

function TMitEigenschaft.getwert: Integer;
begin
  Result := FWert;
end;

end.
