unit Cm.W1050b;

// W1050 WideChar reduced to byte char in set expressions
// Erwartet: W1050
// Zweiter Versuch: Zeichen eines Strings und WideChar-Parameter (#1377).

interface

implementation

function IstKlein(const AText: string; AIndex: Integer): Boolean;
begin
  Result := AText[AIndex] in ['a'..'z', '_']; // <- W1050
end;

function IstLeer(AZeichen: WideChar): Boolean;
begin
  Result := AZeichen in [#9, ' ']; // <- W1050
end;

end.
