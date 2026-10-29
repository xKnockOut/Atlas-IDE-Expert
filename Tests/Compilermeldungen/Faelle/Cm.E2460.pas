unit Cm.E2460;

// E2460 Cannot inherit from special class '%s.%s'
// Erwartet: E2460
// Vermutung zum Code.

interface

type
  TKlasse = class(TCustomAttribute)
  end;

  TMetaKind = class(TClass) // <- E2460
  end;

implementation

end.
