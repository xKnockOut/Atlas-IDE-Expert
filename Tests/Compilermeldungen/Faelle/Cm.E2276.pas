unit Cm.E2276;

// E2276 Identifier '%s' cannot be exported
// Erwartet: E2276
// Vermutung zum Code.

interface

threadvar
  GProFaden: Integer;

implementation

exports
  GProFaden; // <- E2276

end.
