{$J+}
{$WARN ASG_TO_TYPED_CONST ON}
unit Cm.W1017;

// W1017 Assignment to typed constant
// Erwartet: W1017
// Unter {$J-} wäre es E2064; die Warnung ist ohne $WARN aus.

interface

implementation

const
  cZaehler: Integer = 0;

procedure Benutze;
begin
  cZaehler := 1; // <- W1017
end;

end.
