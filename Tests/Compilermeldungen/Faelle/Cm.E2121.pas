unit Cm.E2121;

// E2121 Expression or identifier cannot be exported
// Erwartet: E2121
// Vermutung zum Code.

interface

var
  GZahl: Integer;

implementation

exports
  GZahl; // <- E2121

end.
