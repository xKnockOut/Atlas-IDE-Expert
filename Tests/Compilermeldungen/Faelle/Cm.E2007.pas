unit Cm.E2007;

// E2007 Constant or type identifier expected
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2007.
// Vermutung.

interface

type
  TBereich = 1..-; // <- E2029

implementation

end.
