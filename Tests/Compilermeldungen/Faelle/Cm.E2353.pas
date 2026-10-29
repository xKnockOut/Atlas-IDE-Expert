unit Cm.E2353;

// E2353 Cannot extend sealed class '%s'
// Erwartet: E2353

interface

type
  TVersiegelt = class sealed
  end;

  TKind = class(TVersiegelt) // <- E2353
  end;

implementation

end.
