library CmE2121c;

// E2121 Expression or identifier cannot be exported
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: Variable im exports einer Bibliothek
// (Cm.E2121: Unit in einem Programm, still).

var
  GZahl: Integer;

exports
  GZahl; // <- ohne Meldung

begin
end.
