unit Cm.W1048b;

// W1048 Unsafe typecast
// Erwartet: W1048
// Pointer in eine eigene Klasse statt TObject (#1378).

{$WARN UNSAFE_CAST ON}

interface

implementation

type
  TKunde = class
  end;

function Umwandeln(AZeiger: Pointer): TKunde;
begin
  Result := TKunde(AZeiger); // <- W1048
end;

end.
