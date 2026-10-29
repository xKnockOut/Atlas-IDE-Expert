unit Cm.E2196;

// E2196 Cannot initialize multiple variables
// Erwartet: E2196

interface

var
  GA, GB: Integer = 1; // <- E2196

implementation

end.
