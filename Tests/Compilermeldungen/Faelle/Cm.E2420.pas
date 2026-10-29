unit Cm.E2420;

// E2420 Interface '%s' used in '%s' is not yet completely defined
// Erwartet: E2086
// Delphi 13 meldet hier E2086 statt E2420.

interface

type
  IEins = interface;

  TKlasse = class(TInterfacedObject, IEins) // <- E2086
  end;

  IEins = interface
  end;

implementation

end.
