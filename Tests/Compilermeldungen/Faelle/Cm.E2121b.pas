unit Cm.E2121b;

// E2121 Expression or identifier cannot be exported
// Erwartet: E2276
// Delphi 13 meldet hier E2276 statt E2121.
// Zweiter Versuch: Typ in exports.

interface

type
  TZahl = Integer;

implementation

exports
  TZahl; // <- E2276

end.
