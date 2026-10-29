unit Cm.E2460;

// E2460 Cannot inherit from special class '%s.%s'
// Erwartet: E2021
// Delphi 13 meldet hier E2021 statt E2460.
// Vermutung zum Code.

interface

type
  TKlasse = class(TCustomAttribute)
  end;

  TMetaKind = class(TClass) // <- E2021
  end;

implementation

end.
