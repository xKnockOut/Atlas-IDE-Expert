{$WARN NARROWING_POINTER_CAST ON}
unit Cm.W1076;

// W1076 Typecasting between pointer and narrower integer types
// Erwartet: E1030
// Delphi 13 meldet hier E1030 statt W1076.
// Name der $WARN-Option vermutet.

interface

implementation

function Kuerzen(AZeiger: Pointer): Word;
begin
  Result := Word(AZeiger); // <- E1030
end;

end.
