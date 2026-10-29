unit Cm.E2021b;

// E2021 Class type required
// Erwartet: E2021
// Gegenprobe zu type-kind-required (#1370): einfacher Typ als Vorfahr.

interface

type
  TZahlKlasse = class(Integer) // <- E2021
  end;

implementation

end.
