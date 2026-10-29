unit Cm.E2242;

// E2242 '%s' is not the name of a unit
// Erwartet: E2003
// Delphi 13 meldet hier E2003 statt E2242.

interface

implementation

{$NOINCLUDE Cm.GibtEsNicht} // <- E2003

end.
