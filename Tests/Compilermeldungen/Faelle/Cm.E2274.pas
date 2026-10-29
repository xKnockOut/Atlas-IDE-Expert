unit Cm.E2274;

// E2274 property attribute 'label' cannot be used in dispinterface
// Erwartet: E2274
// Vermutung; aus der .NET-Zeit.

interface

type
  DAnzeige = dispinterface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2274}']
    property Wert: Integer label 'Wert' dispid 1; // <- E2274
  end;

implementation

end.
