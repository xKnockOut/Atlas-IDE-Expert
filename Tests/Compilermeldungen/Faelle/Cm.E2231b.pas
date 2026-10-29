unit Cm.E2231b;

// E2231 '%s' directive not allowed in dispinterface type
// Erwartet: E2231
// Zweiter Versuch (#1374): write an einer Property eines dispinterface.

interface

type
  DAnzeige = dispinterface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2283}']
    procedure SetWert(AWert: Integer); dispid 1;
    property Wert: Integer write SetWert; // <- E2231
  end;

implementation

end.
