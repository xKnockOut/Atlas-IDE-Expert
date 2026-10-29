unit Cm.E2155;

// E2155 Type '%s' needs finalization - not allowed in file type
// Erwartet: E2155

interface

type
  TTextDatei = file of string; // <- E2155

implementation

end.
