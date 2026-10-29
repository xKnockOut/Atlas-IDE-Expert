unit Cm.E2231;

// E2231 '%s' directive not allowed in dispinterface type
// Erwartet: E2231
// Vermutung zum Code: read in einem dispinterface.

interface

type
  DAnzeige = dispinterface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2231}']
    function GetWert: Integer; dispid 1;
    property Wert: Integer read GetWert; // <- E2231
  end;

implementation

end.
