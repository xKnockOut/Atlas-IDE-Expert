unit Cm.E2194;

// E2194 Cannot initialize thread local variables
// Erwartet: E2194

interface

threadvar
  GZahl: Integer = 1; // <- E2194

implementation

end.
