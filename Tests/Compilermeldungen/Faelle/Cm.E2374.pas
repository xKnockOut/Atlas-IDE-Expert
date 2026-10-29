unit Cm.E2374;

// E2374 Cannot make unique type from %s
// Erwartet: E2005
// Delphi 13 meldet hier E2005 statt E2374.
// Vermutung zum Code.

interface

type
  TEigen = type TObject.Create; // <- E2005

implementation

end.
