unit Cm.E2261;

// E2261 Implements clause only allowed for readable property
// Erwartet: E2261

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2261}']
  end;

  TKlasse = class(TInterfacedObject, IEins)
  private
    FEins: IEins;
  public
    property Eins: IEins write FEins implements IEins; // <- E2261
  end;

implementation

end.
