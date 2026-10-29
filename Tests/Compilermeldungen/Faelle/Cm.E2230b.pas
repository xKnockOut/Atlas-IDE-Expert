unit Cm.E2230b;

// E2230 Methods of dispinterface types cannot specify directives
// Erwartet: E2230
// Zweiter Versuch (#1374): safecall und virtual an Methoden eines dispinterface.

interface

type
  DAnzeige = dispinterface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2282}']
    procedure Machen; safecall; dispid 1; // <- E2230
    procedure Zeigen; virtual; dispid 2; // <- E2230
  end;

implementation

end.
