unit Cm.E2420;

// E2420 Interface '%s' used in '%s' is not yet completely defined
// Erwartet: E2420

interface

type
  IEins = interface;

  TKlasse = class(TInterfacedObject, IEins) // <- E2420
  end;

  IEins = interface
  end;

implementation

end.
