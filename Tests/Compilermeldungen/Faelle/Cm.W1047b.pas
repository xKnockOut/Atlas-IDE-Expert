unit Cm.W1047b;

// W1047 Unsafe code
// Erwartet: W1047
// @ auf ein Feld, eine lokale und eine globale Variable (#1378).

{$WARN UNSAFE_CODE ON}

interface

type
  TZaehler = class
  private
    FWert: Integer;
  public
    function Adresse: Pointer;
  end;

var
  GWert: Integer;

implementation

function TZaehler.Adresse: Pointer;
var
  mZahl: Integer;
begin
  mZahl := 0;
  Result := @FWert; // <- W1047
  if mZahl = 0 then
    Result := @mZahl; // <- W1047
  if Result = nil then
    Result := @GWert; // <- W1047
end;

end.
