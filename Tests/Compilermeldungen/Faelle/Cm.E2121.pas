unit Cm.E2121;

// E2121 Expression or identifier cannot be exported
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung zum Code.

interface

var
  GZahl: Integer;

implementation

exports
  GZahl; // <- ohne Meldung

end.
