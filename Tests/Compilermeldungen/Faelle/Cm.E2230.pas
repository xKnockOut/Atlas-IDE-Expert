unit Cm.E2230;

// E2230 Methods of dispinterface types cannot specify directives
// Erwartet: E2230

interface

type
  DAnzeige = dispinterface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2230}']
    procedure Machen; stdcall; dispid 1; // <- E2230
  end;

implementation

end.
