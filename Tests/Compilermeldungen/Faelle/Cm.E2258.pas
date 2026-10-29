unit Cm.E2258;

// E2258 Implements clause only allowed within class types
// Erwartet: E2258

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A3258}']
  end;

  IZwei = interface
    function GetEins: IEins;
    property Eins: IEins read GetEins implements IEins; // <- E2258
  end;

implementation

end.
