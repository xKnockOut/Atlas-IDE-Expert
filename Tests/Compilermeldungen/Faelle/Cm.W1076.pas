{$WARN NARROWING_POINTER_CAST ON}
unit Cm.W1076;

// W1076 Typecasting between pointer and narrower integer types
// Erwartet: W1076
// Name der $WARN-Option vermutet.

interface

implementation

function Kuerzen(AZeiger: Pointer): Word;
begin
  Result := Word(AZeiger); // <- W1076
end;

end.
