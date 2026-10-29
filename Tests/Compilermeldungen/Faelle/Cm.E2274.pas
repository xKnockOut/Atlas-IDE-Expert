unit Cm.E2274;

// E2274 property attribute 'label' cannot be used in dispinterface
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2274.
// Vermutung; aus der .NET-Zeit.

interface

type
  DAnzeige = dispinterface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2274}']
    property Wert: Integer label 'Wert' dispid 1; // <- E2029
  end;

implementation

end.
