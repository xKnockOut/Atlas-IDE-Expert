unit Cm.E2418;

// E2418 Type '%s' needs initialization - not allowed in variant record
// Erwartet: E2418

interface

type
  TVariante = record
    case Integer of
      1: (Zahl: Integer);
      2: (Verweis: IInterface); // <- E2418
  end;

implementation

end.
