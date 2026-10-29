unit Cm.E2209;

// E2209 Field declarations not allowed in interface type
// Erwartet: E2209

interface

type
  IMitFeld = interface
    FWert: Integer; // <- E2209
  end;

implementation

end.
