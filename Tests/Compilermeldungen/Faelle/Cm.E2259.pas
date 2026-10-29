unit Cm.E2259;

// E2259 Implements clause only allowed for properties of class or interface type
// Erwartet: E2259

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2259}']
  end;

  TKlasse = class(TInterfacedObject, IEins)
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert implements IEins; // <- E2259
  end;

implementation

end.
