unit Cm.E2086;

// E2086 Type '%s' is not yet completely defined
// Erwartet: E2086

interface

type
  TKreis = record
    Innen: TKreis; // <- E2086
  end;

implementation

end.
