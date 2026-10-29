unit Cm.E2383;

// E2383 ABSTRACT and SEALED cannot be used together
// Erwartet: E2383

interface

type
  TKlasse = class abstract sealed // <- E2383
  end;

implementation

end.
