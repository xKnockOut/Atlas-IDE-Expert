unit Cm.E2229;

// E2229 A dispinterface type requires an interface identification
// Erwartet: E2229

interface

type
  DAnzeige = dispinterface
    procedure Machen; dispid 1;
  end; // <- E2229

implementation

end.
