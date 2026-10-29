unit Cm.E2527;

// E2527 Helper type '%s' cannot be used in declarations
// Erwartet: E2527

interface

type
  THelfer = class helper for TObject
  end;

implementation

var
  GHelfer: THelfer; // <- E2527

end.
