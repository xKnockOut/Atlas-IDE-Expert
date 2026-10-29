unit Cm.W1030;

// W1030 Invalid compiler directive
// Erwartet: E1030
// Delphi 13 meldet hier E1030 statt W1030.

interface

implementation

{$UNBEKANNTE_DIREKTIVE} // <- E1030

end.
