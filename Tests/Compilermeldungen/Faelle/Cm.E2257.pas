unit Cm.E2257;

// E2257 Duplicate implements clause for interface '%s'
// Erwartet: E2257

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2257}']
  end;

  TKlasse = class(TInterfacedObject, IEins)
  private
    FA: IEins;
    FB: IEins;
  public
    property A: IEins read FA implements IEins;
    property B: IEins read FB implements IEins; // <- E2257
  end;

implementation

end.
