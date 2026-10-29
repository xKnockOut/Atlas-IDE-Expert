unit Cm.E2572;

// E2572 RTTI visibility set constant expression of type System.TRttiVisibility expected
// Erwartet: E2572

interface

{$RTTI EXPLICIT METHODS([1])} // <- E2572

implementation

end.
