unit Cm.E2424;

// E2424 Codepage '%s' is not installed on this machine
// Erwartet: E1030
// Delphi 13 meldet hier E1030 statt E2424.

{$CODEPAGE 99999} // <- E1030

interface

implementation

end.
