unit Cm.E2271;

// E2271 Property getters and setters cannot be overloaded
// Erwartet: E2271
// Vermutung: dcc nimmt passende Überladungen womöglich an (siehe DccFaelle PA6).

interface

type
  TKlasse = class
  private
    function GetWert: Integer; overload;
    function GetWert(AIndex: Integer): Integer; overload;
  public
    property Wert: Integer read GetWert; // <- E2271
  end;

implementation

function TKlasse.GetWert: Integer;
begin
  Result := 0;
end;

function TKlasse.GetWert(AIndex: Integer): Integer;
begin
  Result := AIndex;
end;

end.
