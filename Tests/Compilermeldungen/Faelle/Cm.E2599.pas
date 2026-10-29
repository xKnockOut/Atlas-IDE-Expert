unit Cm.E2599;

// E2599 Field definition not allowed in helper type
// Erwartet: E2599

interface

type
  THelfer = class helper for TObject
  private
    FWert: Integer; // <- E2599
  end;

implementation

end.
