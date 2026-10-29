{$J+}
{$WARN TYPED_CONST_VARPAR ON}
unit Cm.W1016;

// W1016 Typed constant passed as var parameter
// Erwartet: W1016
// Unter {$J-} wäre es E2197; die Warnung ist ohne $WARN aus.

interface

implementation

const
  cZaehler: Integer = 0;

procedure Erhoehen(var AWert: Integer);
begin
  AWert := AWert + 1;
end;

procedure Benutze;
begin
  Erhoehen(cZaehler); // <- W1016
end;

end.
