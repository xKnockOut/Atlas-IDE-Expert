unit Cm.E2418;

// E2418 Type '%s' needs initialization - not allowed in variant record
// Erwartet: E2154
// Delphi 13 meldet hier E2154 statt E2418.

interface

type
  TVariante = record
    case Integer of
      1: (Zahl: Integer);
      2: (Verweis: IInterface); // <- E2154
  end;

implementation

end.
