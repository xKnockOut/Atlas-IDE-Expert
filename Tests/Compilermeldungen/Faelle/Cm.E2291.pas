unit Cm.E2291;

// E2291 Missing implementation of interface method %s.%s
// Erwartet: E2291

interface

type
  IEins = interface
    procedure Machen;
  end;

  TKlasse = class(TInterfacedObject, IEins) // <- E2291
  end;

implementation

end.
