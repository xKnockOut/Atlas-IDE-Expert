unit Cm.E2027;

// E2027 Duplicate tag value
// Erwartet: E2027

interface

type
  TVariante = record
    case Integer of
      1: (Zahl: Integer);
      1: (Zeichen: Char); // <- E2027
  end;

implementation

end.
