unit Cm.E2210;

// E2210 '%s' directive not allowed in in interface type
// Erwartet: E2070
// Delphi 13 meldet hier E2070 statt E2210.

interface

type
  IMitDirektive = interface
    procedure Machen; virtual; // <- E2070
  end;

implementation

end.
