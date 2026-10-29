unit Cm.E2022;

// E2022 Class helper type required
// Erwartet: E2022

interface

type
  THelfer = class helper(TObject) for TObject // <- E2022
  end;

implementation

end.
