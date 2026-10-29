unit Cm.E2175;

// E2175 Field definition not allowed in OLE automation section
// Erwartet: E2175

interface

type
  TAuto = class
  automated
    FWert: Integer; // <- E2175
  end;

implementation

end.
