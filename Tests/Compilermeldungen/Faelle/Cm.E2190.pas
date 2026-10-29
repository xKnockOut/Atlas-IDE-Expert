unit Cm.E2190;

// E2190 Thread local variables cannot be ABSOLUTE
// Erwartet: E2190

interface

var
  GZahl: Integer;

threadvar
  GAuchZahl: Integer absolute GZahl; // <- E2190

implementation

end.
