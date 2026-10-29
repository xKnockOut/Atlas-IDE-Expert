unit Cm.E2121b;

// E2121 Expression or identifier cannot be exported
// Erwartet: E2121
// Zweiter Versuch: Typ in exports.

interface

type
  TZahl = Integer;

implementation

exports
  TZahl; // <- E2121

end.
