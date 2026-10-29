unit Cm.E2154;

// E2154 Type '%s' needs finalization - not allowed in variant record
// Erwartet: E2154

interface

type
  TVariante = record
    case Integer of
      1: (Zahl: Integer);
      2: (Text: string); // <- E2154
  end;

implementation

end.
