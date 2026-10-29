unit Cm.E2549;

// E2549 Cannot declare parameterized type derived from custom attribute class
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

type
  TMarkeAttribute<T> = class(TCustomAttribute) // <- ohne Meldung
  end;

implementation

end.
