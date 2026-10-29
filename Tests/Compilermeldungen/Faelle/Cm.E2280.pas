unit Cm.E2280;

// E2280 Unterminated conditional directive
// Erwartet: E2280

interface

implementation

{$IF Defined(CM_NIE)} // <- E2280

end.
