library CmE2121c;

// E2121 Expression or identifier cannot be exported
// Erwartet: E2121
// Vermutung (#1383): Variable im exports einer Bibliothek (Cm.E2121: Unit in einem Programm, still).

var
  GZahl: Integer;

exports
  GZahl; // <- E2121

begin
end.
