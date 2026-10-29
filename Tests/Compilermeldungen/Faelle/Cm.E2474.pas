unit Cm.E2474;

// E2474 Record type required
// Erwartet: E2474

interface

type
  THelfer = record helper for TObject // <- E2474
  end;

implementation

end.
