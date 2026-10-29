unit Cm.E2374;

// E2374 Cannot make unique type from %s
// Erwartet: E2374
// Vermutung zum Code.

interface

type
  TEigen = type TObject.Create; // <- E2374

implementation

end.
