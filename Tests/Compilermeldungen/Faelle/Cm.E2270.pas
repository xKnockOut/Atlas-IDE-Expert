unit Cm.E2270;

// E2270 Published property getters and setters must have %s calling convention
// Erwartet: E2270

interface

type
  TKlasse = class
  private
    function GetWert: Integer; stdcall;
  published
    property Wert: Integer read GetWert; // <- E2270
  end;

implementation

function TKlasse.GetWert: Integer;
begin
  Result := 0;
end;

end.
