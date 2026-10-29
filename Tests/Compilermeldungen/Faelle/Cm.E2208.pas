unit Cm.E2208;

// E2208 Interface '%s' already implemented by '%s'
// Erwartet: E2208

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2208}']
  end;

  TKlasse = class(TInterfacedObject, IEins, IEins) // <- E2208
  end;

implementation

end.
