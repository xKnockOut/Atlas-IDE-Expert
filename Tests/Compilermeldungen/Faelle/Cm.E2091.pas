unit Cm.E2091;

// E2091 Segment/Offset pairs not supported in Borland 32-bit Pascal
// Erwartet: E2088
// Delphi 13 meldet hier E2088 statt E2091.

interface

var
  GTastatur: Byte absolute $40:$17; // <- E2088

implementation

end.
